import 'package:flutter/material.dart';
import 'package:glopplayer/controllers/player_controller.dart';
import 'package:glopplayer/models/music_genre_category.dart';
import 'package:glopplayer/screens/pages/player_screen.dart';
import 'package:glopplayer/widgets/artwork_thumbnail.dart';
import 'package:glopplayer/widgets/music_list_items.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

class MusicGenresScreen extends StatelessWidget {
  final List<SongModel> songs;
  final List<String> folders;

  const MusicGenresScreen({
    super.key,
    required this.songs,
    this.folders = const [],
  });

  @override
  Widget build(BuildContext context) {
    final categories = MusicGenreCategory.fromSongs(songs, folders: folders);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Categorias')),
      body: categories.isEmpty
          ? const Center(
              child: Text(
                'Não encontramos gêneros nos metadados das músicas.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final category = categories[index];
                final cover = category.songs.first;
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    leading: SizedBox(
                      width: 54,
                      height: 54,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ArtworkThumbnail(
                          id: cover.id,
                          type: ArtworkType.AUDIO,
                          width: 54,
                          height: 54,
                        ),
                      ),
                    ),
                    title: Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${category.songs.length} '
                      '${category.songs.length == 1 ? 'música' : 'músicas'}',
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: scheme.onSurfaceVariant,
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            MusicGenreSongsScreen(category: category),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class MusicGenreSongsScreen extends StatelessWidget {
  final MusicGenreCategory category;

  const MusicGenreSongsScreen({super.key, required this.category});

  void _playSongs(BuildContext context, List<SongModel> songs, int index) {
    context.read<PlayerController>().setPlaylist(songs, initialIndex: index);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstSong = category.songs.first;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(category.name)),
      body: Column(
        children: [
          SizedBox(
            height: 220,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ArtworkThumbnail(
                  id: firstSong.id,
                  type: ArtworkType.AUDIO,
                  height: 220,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x22000000), Color(0xe6000000)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'CATEGORIA',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.4,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        category.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${category.songs.length} '
                        '${category.songs.length == 1 ? 'música' : 'músicas'}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: MusicListItems(
              songs: category.songs,
              onSongTap: (songs, index) => _playSongs(context, songs, index),
            ),
          ),
        ],
      ),
    );
  }
}
