import 'package:flutter/material.dart';
import 'package:glopplayer/controllers/library_controller.dart';
import 'package:glopplayer/models/music_genre_category.dart';
import 'package:glopplayer/screens/pages/music_genres_screen.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

class MusicGenresSection extends StatelessWidget {
  final List<SongModel> songs;

  const MusicGenresSection({super.key, required this.songs});

  @override
  Widget build(BuildContext context) {
    final folders = context.watch<LibraryController>().folders;
    final categories = MusicGenreCategory.fromSongs(songs, folders: folders);
    if (categories.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Explorar por categoria',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Encontre o que combina com você',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _openAll(context, folders),
                child: const Text('Ver todas'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = categories[index];
              final colors = _colorsFor(scheme, index);
              return ActionChip(
                avatar: Icon(
                  _iconFor(category.name),
                  size: 17,
                  color: colors.foreground,
                ),
                label: Text(category.name),
                labelStyle: TextStyle(
                  color: colors.foreground,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: colors.background,
                side:
                    BorderSide(color: colors.foreground.withValues(alpha: .2)),
                onPressed: () => _openCategory(context, category),
              );
            },
          ),
        ),
      ],
    );
  }

  ({Color background, Color foreground}) _colorsFor(
    ColorScheme scheme,
    int index,
  ) {
    final pair = switch (index % 5) {
      0 => (scheme.primaryContainer, scheme.onPrimaryContainer),
      1 => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      2 => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      3 => (scheme.surfaceContainerHighest, scheme.onSurface),
      _ => (scheme.primary.withValues(alpha: .12), scheme.primary),
    };
    return (background: pair.$1, foreground: pair.$2);
  }

  IconData _iconFor(String genre) {
    final normalized = genre.toLowerCase();
    if (normalized.contains('rock') || normalized.contains('metal')) {
      return Icons.electric_bolt;
    }
    if (normalized.contains('funk') ||
        normalized.contains('hip') ||
        normalized.contains('rap')) {
      return Icons.graphic_eq;
    }
    if (normalized.contains('sertanejo') ||
        normalized.contains('country') ||
        normalized.contains('folk')) {
      return Icons.music_note;
    }
    if (normalized.contains('jazz') || normalized.contains('blues')) {
      return Icons.piano;
    }
    if (normalized.contains('pop')) return Icons.star_outline;
    return Icons.headphones;
  }

  void _openAll(BuildContext context, List<String> folders) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MusicGenresScreen(songs: songs, folders: folders),
      ),
    );
  }

  void _openCategory(BuildContext context, MusicGenreCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MusicGenreSongsScreen(category: category),
      ),
    );
  }
}
