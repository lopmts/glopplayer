import 'package:on_audio_query/on_audio_query.dart';

SongModel fakeSongModelFromExternalUri(String uriString) {
  final uri = Uri.parse(uriString);
  final isContentUri = uri.scheme == 'content';

  String displayName;
  String dataPath;

  if (isContentUri) {
    displayName = 'Áudio externo';
    dataPath = uriString; // <- mantém a content:// URI, não zera
  } else {
    dataPath = uri.scheme == 'file' ? uri.toFilePath() : uriString;
    displayName = dataPath.split('/').last;
  }

  return SongModel({
    '_id': -1,
    'title': displayName,
    'artist': 'Arquivo externo',
    'album': null,
    '_data': dataPath,
    'duration': null,
    'is_music': 1,
    'is_podcast': 0,
    'is_ringtone': 0,
    'is_alarm': 0,
    'is_notification': 0,
    'is_audiobook': 0,
  });
}

class MusicLibraryService {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  static const List<String> _excludedPathFragments = [
    '/whatsapp voice notes/',
    '/whatsapp business/media/whatsapp voice notes/',
    '/telegram/telegram voice/',
    '/call recordings/',
    '/callrecordings/',
    '/voice recorder/',
    '/voicerecorder/',
    '/sounds/notifications/',
    '/notifications/',
    '/ringtones/',
    '/alarms/',
    '/record/',
    '/recordings/',
  ];

  Future<bool> checkAndRequestPermission({bool retry = false}) {
    return _audioQuery.checkAndRequest(retryRequest: retry);
  }

  Future<bool> get hasPermission => _audioQuery.permissionsStatus();

  bool _isRealMusic(SongModel song) {
    if (song.isRingtone == true) return false;
    if (song.isNotification == true) return false;
    if (song.isAlarm == true) return false;
    if (song.isPodcast == true) return false;
    if (song.isAudioBook == true) return false;
    if (song.isMusic == false) return false;

    final path = song.data.toLowerCase();
    for (final fragment in _excludedPathFragments) {
      if (path.contains(fragment)) return false;
    }

    return true;
  }

  /// Verifica se [filePath] está dentro de alguma das [folders] (comparação
  /// por prefixo de caminho, case-insensitive). Uma pasta "vazia" na lista
  /// (null/empty) significa "sem restrição" — retorna tudo.
  bool _isInsideAnyFolder(String filePath, List<String> folders) {
    if (folders.isEmpty) return true;

    final normalizedFile = filePath.toLowerCase();
    for (final folder in folders) {
      var normalizedFolder = folder.toLowerCase();
      if (!normalizedFolder.endsWith('/')) {
        normalizedFolder = '$normalizedFolder/';
      }
      if (normalizedFile.startsWith(normalizedFolder)) return true;
    }
    return false;
  }

  /// [restrictToFolders]: se vazio ou null, retorna músicas de qualquer
  /// pasta (comportamento padrão). Se tiver pastas, só retorna músicas
  /// cujo caminho está dentro de alguma delas — usado quando o usuário
  /// configurou pastas específicas em "Local Library".
  Future<List<SongModel>> fetchAllSongs(
      {List<String>? restrictToFolders}) async {
    final songs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    final folders = restrictToFolders ?? const [];
    return songs
        .where(_isRealMusic)
        .where((s) => _isInsideAnyFolder(s.data, folders))
        .toList();
  }

  /// Álbuns são derivados a partir das músicas já filtradas (real + dentro
  /// das pastas configuradas) — só aparece álbum que tem pelo menos 1
  /// música válida dentro do escopo selecionado.
  Future<List<AlbumModel>> fetchAllAlbums(
      {List<String>? restrictToFolders}) async {
    final albums = await _audioQuery.queryAlbums(
      sortType: AlbumSortType.ALBUM,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    final realSongs = await fetchAllSongs(restrictToFolders: restrictToFolders);
    final validAlbumIds =
        realSongs.map((s) => s.albumId).whereType<int>().toSet();

    return albums.where((a) => validAlbumIds.contains(a.id)).toList();
  }

  Future<List<SongModel>> fetchSongsFromAlbum(
    int albumId, {
    List<String>? restrictToFolders,
  }) async {
    final songs = await _audioQuery.queryAudiosFrom(
      AudiosFromType.ALBUM_ID,
      albumId,
    );

    final folders = restrictToFolders ?? const [];
    return songs
        .where(_isRealMusic)
        .where((s) => _isInsideAnyFolder(s.data, folders))
        .toList();
  }
}
