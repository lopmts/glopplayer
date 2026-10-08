import 'package:on_audio_query/on_audio_query.dart';
import 'package:glopplayer/widgets/song_list/song_filter_engine.dart';

class MusicGenreCategory {
  final String name;
  final List<SongModel> songs;

  const MusicGenreCategory({
    required this.name,
    required this.songs,
  });

  static List<MusicGenreCategory> fromSongs(
    List<SongModel> songs, {
    List<String> folders = const [],
  }) {
    final filter = SongFilterEngine();
    final categories = filter.availableGenres(songs, folders).map((genre) {
      filter.genreFilter = genre;
      return MusicGenreCategory(
        name: genre,
        songs: List.unmodifiable(filter.filteredSongs(songs, folders)),
      );
    }).toList();

    categories.sort((a, b) {
      final byCount = b.songs.length.compareTo(a.songs.length);
      return byCount != 0 ? byCount : a.name.compareTo(b.name);
    });
    return categories;
  }
}
