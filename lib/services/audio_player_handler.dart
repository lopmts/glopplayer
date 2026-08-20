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

    // NOVO — resolve a artwork da PRIMEIRA faixa do próximo álbum de forma
    // bloqueante, pra garantir que ela já esteja pronta quando a troca
    // de faixa acontecer (é essa faixa que vai aparecer na notificação
    // primeiro; o resto do álbum pode resolver em background com calma)
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

    // Resto do álbum resolve em background, sem bloquear
    _resolveArtworkForRange(songs, updatedQueue, offset);
  }

  // Refatorado a partir do _resolveArtworkInBackground original, agora
  // aceita um offset pra funcionar tanto na carga inicial (offset 0)
  // quanto no append (offset = tamanho da queue antes de anexar)
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
    });
  }

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
    // Prioriza a música atual primeiro (feedback visual mais rápido pro usuário)
    final order = [initialIndex, ...List.generate(songs.length, (i) => i)]
        .toSet() // remove duplicata do initialIndex
        .toList();

    for (final i in order) {
      final song = songs[i];
      final cacheKey = song.albumId ?? song.id;
      if (_artworkCache.containsKey(cacheKey)) continue; // já resolvido

      final artUri = await _artworkFileUri(song);
      if (artUri == null) continue;

      // Atualiza o MediaItem já existente na queue com a artwork nova
      final updated = items[i].copyWith(artUri: artUri);
      items[i] = updated;
      queue.add(List.of(items));

      // Se for a música tocando agora, atualiza a notificação também
      if (mediaItem.value?.id == updated.id) {
        mediaItem.add(updated);
      }
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) await _player.seekToPrevious();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
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
