import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final Map<int, Uri?> _artworkCache = {};

  ConcatenatingAudioSource? _currentSource;

  AudioPlayer get player => _player;

  // ---- CROSSFADE -----------------------------------------------------
  // Player secundário e independente, usado só durante a janela de
  // transição. Fica ocioso (sem AudioSource) o resto do tempo.
  final AudioPlayer _crossfadePlayer = AudioPlayer();

  bool _crossfadeEnabled = false;
  Duration _crossfadeDuration = const Duration(seconds: 4);
  static const _crossfadeTriggerMargin = Duration(milliseconds: 300);
  static const _crossfadeStepInterval = Duration(milliseconds: 100);

  bool _crossfading = false; // fade em andamento
  bool _crossfadeArmed = false; // já disparado pra ESTA faixa (evita retrigger)
  Timer? _crossfadeTimer;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _crossfadePlayerStateSub;

  /// Chamado pela tela de configurações (via PlayerController) sempre que
  /// o usuário muda o toggle ou a duração.
  void updateCrossfadeSettings({
    required bool enabled,
    required Duration duration,
  }) {
    _crossfadeEnabled = enabled;
    _crossfadeDuration = duration;
    if (!enabled) {
      unawaited(_cancelCrossfade(restoreVolume: true));
    }
  }
  // ----------------------------------------------------------------------

  MyAudioHandler() {
    _init();
  }

  String _resolveSongUri(SongModel song) {
    final path = song.data;
    if (path.isNotEmpty) {
      return Uri.file(path).toString();
    }
    return song.uri ?? '';
  }

  Future<void> setSongs(List<SongModel> songs, {int initialIndex = 0}) async {
    await _cancelCrossfade(
        restoreVolume: true); // NOVO — troca de fila cancela fade

    final items = <MediaItem>[];
    final sources = <AudioSource>[];

    for (final song in songs) {
      final cacheKey = song.albumId ?? song.id;
      final cachedArt = _artworkCache[cacheKey];
      final resolvedId = _resolveSongUri(song);

      final item = MediaItem(
        id: resolvedId,
        title: song.title,
        artist: song.artist ?? 'Artista desconhecido',
        album: song.album ?? 'Álbum desconhecido',
        duration: song.duration != null
            ? Duration(milliseconds: song.duration!)
            : null,
        artUri: cachedArt,
      );
      items.add(item);
      sources.add(AudioSource.uri(Uri.parse(item.id), tag: item));
    }

    queue.add(items);

    final source = ConcatenatingAudioSource(children: sources);
    try {
      await _player.setAudioSource(source, initialIndex: initialIndex);
      _currentSource = source; // NOVO — só guarda se deu certo
    } catch (e) {
      debugPrint('ERRO AO CARREGAR PLAYLIST: $e');
      return;
    }

    if (items.isNotEmpty) {
      mediaItem.add(items[initialIndex]);
    }

    _resolveArtworkInBackground(songs, items, initialIndex);
  }

  // NOVO — anexa músicas à playlist atual sem recriar o AudioSource
  // (é isso que evita o corte/pausa na transição)
  Future<void> appendSongs(List<SongModel> songs) async {
    if (_currentSource == null || songs.isEmpty) return;

    final newItems = <MediaItem>[];
    final newSources = <AudioSource>[];

    for (final song in songs) {
      final cacheKey = song.albumId ?? song.id;
      final cachedArt = _artworkCache[cacheKey];
      final resolvedId = _resolveSongUri(song);

      final item = MediaItem(
        id: resolvedId,
        title: song.title,
        artist: song.artist ?? 'Artista desconhecido',
        album: song.album ?? 'Álbum desconhecido',
        duration: song.duration != null
            ? Duration(milliseconds: song.duration!)
            : null,
        artUri: cachedArt,
      );
      newItems.add(item);
      newSources.add(AudioSource.uri(Uri.parse(item.id), tag: item));
    }

    try {
      await _currentSource!.addAll(newSources);
    } catch (e) {
      debugPrint('ERRO AO ANEXAR PRÓXIMO ÁLBUM: $e');
      return;
    }

    var updatedQueue = List<MediaItem>.of(queue.value)..addAll(newItems);
    final offset = updatedQueue.length - newItems.length;
    queue.add(updatedQueue);

    if (songs.isNotEmpty) {
      final firstSong = songs.first;
      final cacheKey = firstSong.albumId ?? firstSong.id;
      if (!_artworkCache.containsKey(cacheKey)) {
        final artUri = await _artworkFileUri(firstSong);
        if (artUri != null) {
          final updatedFirst = updatedQueue[offset].copyWith(artUri: artUri);
          updatedQueue = List.of(updatedQueue)..[offset] = updatedFirst;
          queue.add(updatedQueue);

          if (mediaItem.value?.id == updatedFirst.id) {
            mediaItem.add(updatedFirst);
          }
        }
      }
    }

    _resolveArtworkForRange(songs, updatedQueue, offset);
  }

  Future<void> insertSongsNext(List<SongModel> songs) async {
    if (_currentSource == null || songs.isEmpty) return;

    final items = <MediaItem>[];
    final sources = <AudioSource>[];
    for (final song in songs) {
      final cacheKey = song.albumId ?? song.id;
      final item = MediaItem(
        id: _resolveSongUri(song),
        title: song.title,
        artist: song.artist ?? 'Artista desconhecido',
        album: song.album ?? 'Álbum desconhecido',
        duration: song.duration != null
            ? Duration(milliseconds: song.duration!)
            : null,
        artUri: _artworkCache[cacheKey],
      );
      items.add(item);
      sources.add(AudioSource.uri(Uri.parse(item.id), tag: item));
    }

    final currentIndex = _player.currentIndex ?? 0;
    final insertIndex = currentIndex + 1;
    await _currentSource!.insertAll(insertIndex, sources);

    final updatedQueue = List<MediaItem>.of(queue.value)
      ..insertAll(insertIndex, items);
    queue.add(updatedQueue);
    _resolveArtworkForRange(songs, updatedQueue, insertIndex);
  }

  Future<void> _resolveArtworkForRange(
    List<SongModel> songs,
    List<MediaItem> fullQueueItems,
    int offset,
  ) async {
    for (var i = 0; i < songs.length; i++) {
      final song = songs[i];
      final cacheKey = song.albumId ?? song.id;
      if (_artworkCache.containsKey(cacheKey)) continue;

      final artUri = await _artworkFileUri(song);
      if (artUri == null) continue;

      final globalIndex = offset + i;
      if (globalIndex >= fullQueueItems.length) continue;

      final updated = fullQueueItems[globalIndex].copyWith(artUri: artUri);
      fullQueueItems[globalIndex] = updated;
      queue.add(List.of(fullQueueItems));

      if (mediaItem.value?.id == updated.id) {
        mediaItem.add(updated);
      }
    }
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        debugPrint('ERRO DE REPRODUÇÃO: $e');
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
        ));
      },
    );

    _player.currentIndexStream.listen((index) {
      final items = queue.value;
      if (index != null && index >= 0 && index < items.length) {
        mediaItem.add(items[index]);
      }
      // Toda vez que o índice muda (seja por handoff manual do crossfade
      // ou avanço natural), a faixa é "nova" -> pode disparar crossfade
      // de novo quando chegar perto do fim dela.
      _crossfadeArmed = false;
    });

    // NOVO — monitor de posição pra disparar o crossfade
    _positionSub = _player.positionStream.listen(_maybeStartCrossfade);
  }

  // ---- CROSSFADE: lógica principal ------------------------------------

  void _maybeStartCrossfade(Duration position) {
    if (!_crossfadeEnabled) return;
    if (_crossfading || _crossfadeArmed) return;
    if (!_player.playing) return;
    if (_crossfadeDuration <= Duration.zero) return;

    final duration = _player.duration;
    if (duration == null || duration == Duration.zero) return;

    final nextIndex = _player.nextIndex;
    if (nextIndex == null)
      return; // não tem próxima faixa -> deixa tocar normal

    final triggerAt = duration - _crossfadeDuration - _crossfadeTriggerMargin;
    if (triggerAt <= Duration.zero)
      return; // faixa curta demais pro fade configurado
    if (position < triggerAt) return;

    _crossfadeArmed = true;
    unawaited(_startCrossfade(nextIndex));
  }

  Future<void> _startCrossfade(int nextIndex) async {
    if (_crossfading) return;
    final items = queue.value;
    if (nextIndex < 0 || nextIndex >= items.length) return;

    final nextItem = items[nextIndex];
    if (nextItem.id.isEmpty) return;

    _crossfading = true;

    try {
      await _crossfadePlayer.setVolume(0);
      await _crossfadePlayer.setUrl(nextItem.id, preload: true);
    } catch (e) {
      debugPrint('ERRO AO PRÉ-CARREGAR CROSSFADE: $e');
      _crossfading = false;
      return;
    }

    // Se o usuário mudou algo (pausou, pulou) enquanto a gente preparava,
    // aborta antes de começar a tocar por cima.
    if (!_crossfading || !_player.playing) {
      await _crossfadePlayer.stop();
      _crossfading = false;
      return;
    }

    unawaited(_crossfadePlayer.play());

    final totalMs = _crossfadeDuration.inMilliseconds;
    final stepMs = _crossfadeStepInterval.inMilliseconds;
    var elapsedMs = 0;

    final completer = Completer<void>();
    _crossfadeTimer = Timer.periodic(_crossfadeStepInterval, (timer) async {
      elapsedMs += stepMs;
      final t = (elapsedMs / totalMs).clamp(0.0, 1.0);

      try {
        await Future.wait([
          _player.setVolume(1.0 - t),
          _crossfadePlayer.setVolume(t),
        ]);
      } catch (_) {
        // players podem ter sido descartados/trocados no meio do fade
      }

      if (t >= 1.0) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });

    await completer.future;

    // Handoff: se ainda estamos numa transição válida (não foi cancelada
    // no meio pelo usuário), troca o player principal pro próximo índice
    // na posição em que o player de crossfade já está.
    if (_crossfading) {
      final handoffPosition = _crossfadePlayer.position;
      try {
        await _player.seek(handoffPosition, index: nextIndex);
        await _player.setVolume(1.0);
      } catch (e) {
        debugPrint('ERRO NO HANDOFF DO CROSSFADE: $e');
        await _player.setVolume(1.0); // nunca deixa o player principal mudo
      }
    }

    await _crossfadePlayer.stop();
    _crossfading = false;
  }

  /// Cancela um crossfade em andamento (ou uma preparação em progresso),
  /// restaurando o volume do player principal. Chamado em qualquer ação
  /// explícita do usuário que deveria interromper a transição suave
  /// (pular, pausar, buscar posição, trocar de fila).
  Future<void> _cancelCrossfade({required bool restoreVolume}) async {
    if (!_crossfading && _crossfadeTimer == null) return;

    _crossfading = false;
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;

    try {
      await _crossfadePlayer.stop();
    } catch (_) {}

    if (restoreVolume) {
      try {
        await _player.setVolume(1.0);
      } catch (_) {}
    }
  }

  // -----------------------------------------------------------------------

  Future<Uri?> _artworkFileUri(SongModel song) async {
    final cacheKey = song.albumId ?? song.id;
    if (_artworkCache.containsKey(cacheKey)) {
      return _artworkCache[cacheKey];
    }
    try {
      final bytes = await _audioQuery.queryArtwork(
        song.id,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 300,
        quality: 90,
      );
      if (bytes == null || bytes.isEmpty) {
        _artworkCache[cacheKey] = null;
        return null;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/artwork_$cacheKey.jpg');
      await file.writeAsBytes(bytes, flush: true);
      final uri = Uri.file(file.path);
      _artworkCache[cacheKey] = uri;
      return uri;
    } catch (_) {
      _artworkCache[cacheKey] = null;
      return null;
    }
  }

  Future<void> _resolveArtworkInBackground(
    List<SongModel> songs,
    List<MediaItem> items,
    int initialIndex,
  ) async {
    final order = [initialIndex, ...List.generate(songs.length, (i) => i)]
        .toSet()
        .toList();

    for (final i in order) {
      final song = songs[i];
      final cacheKey = song.albumId ?? song.id;
      if (_artworkCache.containsKey(cacheKey)) continue;

      final artUri = await _artworkFileUri(song);
      if (artUri == null) continue;

      final updated = items[i].copyWith(artUri: artUri);
      items[i] = updated;
      queue.add(List.of(items));

      if (mediaItem.value?.id == updated.id) {
        mediaItem.add(updated);
      }
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() async {
    // NOVO — pausar durante um crossfade cancela o fade de forma limpa
    await _cancelCrossfade(restoreVolume: true);
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    // NOVO — busca manual de posição invalida qualquer fade em andamento
    await _cancelCrossfade(restoreVolume: true);
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    // NOVO — pulo manual cancela o fade (o handoff automático não se aplica)
    await _cancelCrossfade(restoreVolume: true);
    if (_player.hasNext) await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _cancelCrossfade(restoreVolume: true);
    if (_player.hasPrevious) await _player.seekToPrevious();
  }

  @override
  Future<void> stop() async {
    await _cancelCrossfade(restoreVolume: false);
    await _player.stop();
    await super.stop();
  }

  Future<void> dispose() async {
    await _positionSub?.cancel();
    await _crossfadePlayerStateSub?.cancel();
    _crossfadeTimer?.cancel();
    await _crossfadePlayer.dispose();
    await _player.dispose();
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
      },
      androidCompactActionIndices: const [0, 1],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }
}
