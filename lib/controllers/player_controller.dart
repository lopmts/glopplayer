import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:glopplayer/services/crossfade_settings_service.dart';
import 'package:glopplayer/services/music_library_service.dart';
import 'package:glopplayer/services/playback_persistence_service.dart';
import 'package:glopplayer/services/recently_played_service.dart';
import 'package:home_widget/home_widget.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../services/audio_player_handler.dart';

class PlayerController extends ChangeNotifier {
  final MyAudioHandler _handler;
  final MusicLibraryService _library; // NOVO — injetado
  final RecentlyPlayedService _recentlyPlayed; // NOVO — histórico de reprodução
  final PlaybackPersistenceService _persistence = PlaybackPersistenceService();
  final CrossfadeSettingsService
      _crossfadeSettings; // NOVO — settings de crossfade
  Future<void>? _pendingAlbumAppend;

  List<SongModel> _playlist = [];
  int _currentIndex = 0;
  int _loadToken = 0;
  bool _isPlaying = false;
  bool _suppressIndexStream = false;
  Timer? _saveDebounce;

  // NOVO — rastreamento do "álbum atual" dentro da fila concatenada
  AlbumModel? _currentAlbum;
  int _currentAlbumStartIndex = 0;
  int _currentAlbumLength = 0;
  bool _nextAlbumAppended = false;
  AlbumModel? _pendingNextAlbum;
  int _pendingNextAlbumLength = 0;

  final _playlistCompletedController = StreamController<void>.broadcast();
  Stream<void> get playlistCompleted => _playlistCompletedController.stream;

  AudioPlayer get player => _handler.player;
  List<SongModel> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  AlbumModel? get currentAlbum => _currentAlbum; // NOVO — útil pra UI
  SongModel? get currentSong =>
      _playlist.isEmpty ? null : _playlist[_currentIndex];
  bool get hasPlaylist => _playlist.isNotEmpty;
  List<SongModel> get songs => _playlist;

  // NOVO — expõe as preferências de crossfade pra tela de configurações
  CrossfadeSettingsService get crossfadeSettings => _crossfadeSettings;

  bool isCurrentSong(SongModel song) =>
      currentSong != null && currentSong!.id == song.id;

  bool isCurrentlyPlaying(SongModel song) => isCurrentSong(song) && _isPlaying;

  // NOVO — ponto de entrada usado pela AlbumSongsScreen no lugar de setPlaylist
  Future<void> playAlbum(
    AlbumModel album,
    List<SongModel> songs, {
    int initialIndex = 0,
  }) async {
    _currentAlbum = album;
    _currentAlbumStartIndex = 0;
    _currentAlbumLength = songs.length;
    _nextAlbumAppended = false;
    _pendingNextAlbum = null;
    _pendingNextAlbumLength = 0;

    await setPlaylist(songs, initialIndex: initialIndex);
  }

  PlayerController(
    this._handler, {
    MusicLibraryService? library,
    RecentlyPlayedService? recentlyPlayed,
    CrossfadeSettingsService? crossfadeSettings, // NOVO
  })  : _library = library ?? MusicLibraryService(),
        _recentlyPlayed = recentlyPlayed ?? RecentlyPlayedService(),
        _crossfadeSettings = crossfadeSettings ?? CrossfadeSettingsService() {
    _handler.player.currentIndexStream.listen((index) {
      if (_suppressIndexStream) return;
      if (index != null &&
          index >= 0 &&
          index < _playlist.length &&
          index != _currentIndex) {
        _currentIndex = index;
        notifyListeners();
        _maybeAdvanceAlbumQueue(); // NOVO
        unawaited(_saveWidgetState());
        unawaited(_recordCurrentPlay()); // NOVO — histórico
      }
    });

    _handler.player.positionStream.listen((_) => _schedulePositionSave());

    _handler.player.playingStream.listen((playing) {
      _isPlaying = playing;
      notifyListeners();
      unawaited(_saveWidgetState());
    });

    _handler.player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _playlistCompletedController.add(null);
        _handleUnexpectedCompletion(); // NOVO — fallback de segurança
      }
    });

    unawaited(_initCrossfadeSettings()); // NOVO
  }

  // NOVO — carrega preferência salva e aplica no handler; reaplica sempre
  // que a UI de configurações mudar algo (toggle ou slider)
  Future<void> _initCrossfadeSettings() async {
    if (!_crossfadeSettings.isLoaded) {
      await _crossfadeSettings.load();
    }
    _applyCrossfadeSettings();
    _crossfadeSettings.addListener(_applyCrossfadeSettings);
  }

  void _applyCrossfadeSettings() {
    _handler.updateCrossfadeSettings(
      enabled: _crossfadeSettings.enabled,
      duration: _crossfadeSettings.duration,
    );
  }

  // NOVO — registra a faixa atual no histórico de "tocadas recentemente"
  Future<void> _recordCurrentPlay() async {
    final song = currentSong;
    if (song == null) return;
    try {
      await _recentlyPlayed.recordPlay(song);
    } catch (_) {
      // Histórico é "best effort" — falha aqui não deve afetar a reprodução
    }
  }

  Future<void> _appendNextAlbumInQueue() async {
    if (_currentAlbum == null) return;
    if (_pendingAlbumAppend != null) return; // já tem um em andamento

    final future = _doAppendNextAlbum();
    _pendingAlbumAppend = future;
    try {
      await future;
    } finally {
      _pendingAlbumAppend = null;
    }
  }

  Future<void> _doAppendNextAlbum() async {
    final albums = await _library.fetchAllAlbums();
    if (albums.isEmpty) return;

    final idx = albums.indexWhere((a) => a.id == _currentAlbum!.id);
    if (idx == -1) return;

    final nextIndex = (idx + 1) % albums.length;
    final nextAlbum = albums[nextIndex];

    final nextSongs = await _library.fetchSongsFromAlbum(nextAlbum.id);
    if (nextSongs.isEmpty) return;

    _pendingNextAlbum = nextAlbum;
    _pendingNextAlbumLength = nextSongs.length;

    await appendToPlaylist(nextSongs);
  }

  // ALTERADO — next() agora garante que existe próxima faixa antes de pular
  Future<void> next() async {
    if (!_handler.player.hasNext) {
      // Se já tem um append rolando, espera ele. Senão, dispara na hora
      // (cobre o caso do usuário abrir o álbum já na última faixa e
      // clicar "próxima" antes do trigger natural ter tido chance de rodar)
      if (_pendingAlbumAppend != null) {
        await _pendingAlbumAppend;
      } else if (_currentAlbum != null) {
        await _appendNextAlbumInQueue();
      }
    }
    await _handler.skipToNext();
  }

  // NOVO — decide quando anexar o próximo álbum e quando "cruzar a fronteira"
  void _maybeAdvanceAlbumQueue() {
    if (_currentAlbum == null || _currentAlbumLength == 0) return;

    final relativeIndex = _currentIndex - _currentAlbumStartIndex;

    // Cruzou pra dentro do álbum que já tinha sido anexado?
    if (_pendingNextAlbum != null && relativeIndex >= _currentAlbumLength) {
      _currentAlbum = _pendingNextAlbum;
      _currentAlbumStartIndex += _currentAlbumLength;
      _currentAlbumLength = _pendingNextAlbumLength;
      _nextAlbumAppended = false;
      _pendingNextAlbum = null;
      _pendingNextAlbumLength = 0;
      return;
    }

    // Ainda dentro do álbum atual, mas perto do fim -> anexa o próximo
    final triggerRelative =
        (_currentAlbumLength - 2).clamp(0, _currentAlbumLength - 1);
    if (!_nextAlbumAppended && relativeIndex >= triggerRelative) {
      _nextAlbumAppended = true;
      _appendNextAlbumInQueue();
    }
  }

  // Fallback: só deveria disparar se o append acima falhou por algum
  // motivo (ex: erro de I/O) e o player realmente ficou sem conteúdo
  Future<void> _handleUnexpectedCompletion() async {
    if (_pendingNextAlbum != null) {
      // já tínhamos anexado, só garante que voltou a tocar
      await _handler.play();
      return;
    }
    // não tinha nada anexado ainda -> tenta recuperar do zero
    await _appendNextAlbumInQueue();
    await _handler.play();
  }

  Future<void> appendToPlaylist(List<SongModel> songs) async {
    if (songs.isEmpty) return;
    _playlist = [..._playlist, ...songs];
    notifyListeners();
    await _handler.appendSongs(songs);
    _savePlaybackState();
    unawaited(_saveWidgetState());
  }

  Future<void> addNextInQueue(SongModel song) async {
    if (_playlist.isEmpty) {
      await setPlaylist([song]);
      return;
    }

    final insertIndex = _currentIndex + 1;
    final updatedPlaylist = List<SongModel>.of(_playlist)
      ..insert(insertIndex, song);
    _playlist = updatedPlaylist;
    if (_currentAlbum != null &&
        insertIndex <= _currentAlbumStartIndex + _currentAlbumLength) {
      _currentAlbumLength++;
    }
    notifyListeners();
    await _handler.insertSongsNext([song]);
    await _savePlaybackState();
  }

  Future<void> _saveWidgetState() async {
    final mediaItem = _handler.mediaItem.value;
    final title = mediaItem?.title ?? currentSong?.title ?? '';
    final artist = mediaItem?.artist ?? currentSong?.artist ?? '';
    final artworkPath = mediaItem?.artUri?.path ?? '';

    await Future.wait([
      HomeWidget.saveWidgetData<String>('title', title),
      HomeWidget.saveWidgetData<String>('artist', artist),
      HomeWidget.saveWidgetData<String>('artworkPath', artworkPath),
      HomeWidget.saveWidgetData<bool>('isPlaying', _isPlaying),
    ]);

    await HomeWidget.updateWidget(
      qualifiedAndroidName: 'com.glopblog.glopplayer.PlayerWidgetProvider',
    );
  }

  void _schedulePositionSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 3), _savePlaybackState);
  }

  Future<void> playQueue(List<SongModel> songs, {int initialIndex = 0}) async {
    _currentAlbum = null;
    _currentAlbumStartIndex = 0;
    _currentAlbumLength = 0;
    _nextAlbumAppended = false;
    _pendingNextAlbum = null;
    _pendingNextAlbumLength = 0;

    await setPlaylist(songs, initialIndex: initialIndex);
  }

  Future<void> _savePlaybackState() async {
    if (_playlist.isEmpty) return;
    final refs = _playlist
        .where((song) => song.data.isNotEmpty)
        .map((song) => {'path': song.data})
        .toList();
    if (refs.isEmpty) return;
    await _persistence.save(
      songRefs: refs,
      currentIndex: _currentIndex,
      positionMs: _handler.player.position.inMilliseconds,
    );
  }

  Future<void> restoreLastSession() async {
    final saved = await _persistence.load();
    if (saved == null) return;

    final rawSongs = saved['songs'];
    if (rawSongs is! List) return;

    final savedPaths = rawSongs
        .whereType<Map>()
        .map((ref) => ref['path'])
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList();
    if (savedPaths.isEmpty) return;

    final librarySongs = await _library.fetchAllSongs();
    final songsByPath = {
      for (final song in librarySongs) song.data: song,
    };
    final songs = savedPaths
        .map((path) => songsByPath[path])
        .whereType<SongModel>()
        .toList();
    if (songs.isEmpty) return;

    final savedIndex = saved['currentIndex'];
    final index =
        savedIndex is int ? savedIndex.clamp(0, songs.length - 1).toInt() : 0;
    final savedPosition = saved['positionMs'];
    final positionMs =
        savedPosition is int && savedPosition > 0 ? savedPosition : 0;

    await setPlaylist(songs, initialIndex: index, autoPlay: false);
    if (positionMs > 0) {
      await _handler.seek(Duration(milliseconds: positionMs));
    }
    await _handler.pause();
    await _savePlaybackState();
  }

  Future<void> setPlaylist(List<SongModel> songs,
      {int initialIndex = 0, bool autoPlay = true}) async {
    final token = ++_loadToken;
    _suppressIndexStream = true;
    _playlist = songs;
    _currentIndex = initialIndex;
    notifyListeners();

    await _handler.setSongs(songs, initialIndex: initialIndex);
    if (token != _loadToken) return;

    _suppressIndexStream = false;
    if (autoPlay) {
      await _handler.play();
    } else {
      await _handler.pause();
    }

    _savePlaybackState();
    unawaited(_saveWidgetState());
    unawaited(_recordCurrentPlay()); // NOVO — histórico (cobre a 1ª faixa,
    // que não passa pelo listener de currentIndexStream por já começar
    // no índice certo)
  }

  Future<void> playPause() async {
    if (_handler.player.playing) {
      await _handler.pause();
    } else {
      await _handler.play();
    }
  }

  Future<void> previous() => _handler.skipToPrevious();
  Future<void> seek(Duration position) => _handler.seek(position);

  void playSong(SongModel song) {}

  Future<void> playExternalFile(String uriString) async {
    // Arquivo externo não pertence a um álbum -> zera o contexto de álbum
    _currentAlbum = null;
    _currentAlbumLength = 0;
    _pendingNextAlbum = null;

    final fakeSong = fakeSongModelFromExternalUri(uriString);
    await setPlaylist([fakeSong], initialIndex: 0);
  }

  @override
  void dispose() {
    _crossfadeSettings.removeListener(_applyCrossfadeSettings); // NOVO
    _saveDebounce?.cancel();
    _playlistCompletedController.close();
    super.dispose();
  }
}
