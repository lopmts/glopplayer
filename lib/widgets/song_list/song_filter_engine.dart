import 'package:on_audio_query/on_audio_query.dart';
import '../../utils/audio_type_utils.dart';

/// Toda a lógica de busca/filtro (texto, artista, gênero, tipo de arquivo)
/// que antes vivia espalhada dentro de _MusicListScreenState. De propósito
/// NÃO é um ChangeNotifier -- quem usa essa classe (a State) decide quando
/// chamar setState; aqui só ficam dados + funções puras de cálculo.
class SongFilterEngine {
  String query = '';
  String? artistFilter;
  String? genreFilter;
  String? typeFilter;

  bool get hasActiveFilter =>
      artistFilter != null || genreFilter != null || typeFilter != null;

  void clear() {
    artistFilter = null;
    genreFilter = null;
    typeFilter = null;
  }

  static String _artistLabel(SongModel song) =>
      song.artist?.trim().isNotEmpty == true
          ? song.artist!.trim()
          : 'Artista desconhecido';

  static String _genreLabel(SongModel song) =>
      song.genre?.trim().isNotEmpty == true ? song.genre!.trim() : 'Sem gênero';

  static String _typeLabel(SongModel song) => audioTypeFromPath(song.data);

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

  /// Aplica só o escopo de pastas -- base usada tanto pra lista final
  /// quanto pra calcular as opções disponíveis nos dropdowns.
  Iterable<SongModel> folderScoped(
      List<SongModel> songs, List<String> folders) {
    if (folders.isEmpty) return songs;
    return songs.where((song) => _isInsideAnyFolder(song.data, folders));
  }

  List<SongModel> filteredSongs(List<SongModel> songs, List<String> folders) {
    Iterable<SongModel> base = folderScoped(songs, folders);

    if (artistFilter != null) {
      base = base.where((s) => _artistLabel(s) == artistFilter);
    }
    if (genreFilter != null) {
      base = base.where((s) => _genreLabel(s) == genreFilter);
    }
    if (typeFilter != null) {
      base = base.where((s) => _typeLabel(s) == typeFilter);
    }
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      base = base.where((song) {
        final title = song.title.toLowerCase();
        final artist = (song.artist ?? '').toLowerCase();
        return title.contains(q) || artist.contains(q);
      });
    }

    return base.toList();
  }

  // Cada "available*" respeita os OUTROS filtros ativos (não o próprio),
  // pra os dropdowns ficarem combináveis em vez de "encolher" pra uma
  // única opção assim que algo é selecionado -- mesmo princípio que já
  // existia pra artista/gênero, só estendido pro tipo.

  List<String> availableArtists(List<SongModel> songs, List<String> folders) {
    Iterable<SongModel> base = folderScoped(songs, folders);
    if (genreFilter != null)
      base = base.where((s) => _genreLabel(s) == genreFilter);
    if (typeFilter != null)
      base = base.where((s) => _typeLabel(s) == typeFilter);
    final set = base.map(_artistLabel).toSet().toList()..sort();
    return set;
  }

  List<String> availableGenres(List<SongModel> songs, List<String> folders) {
    Iterable<SongModel> base = folderScoped(songs, folders);
    if (artistFilter != null)
      base = base.where((s) => _artistLabel(s) == artistFilter);
    if (typeFilter != null)
      base = base.where((s) => _typeLabel(s) == typeFilter);
    final set = base.map(_genreLabel).toSet().toList()..sort();
    return set;
  }

  List<String> availableTypes(List<SongModel> songs, List<String> folders) {
    Iterable<SongModel> base = folderScoped(songs, folders);
    if (artistFilter != null)
      base = base.where((s) => _artistLabel(s) == artistFilter);
    if (genreFilter != null)
      base = base.where((s) => _genreLabel(s) == genreFilter);
    final set = base.map(_typeLabel).toSet().toList()..sort();
    return set;
  }
}
