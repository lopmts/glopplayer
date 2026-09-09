import 'package:flutter/material.dart';

class ActiveFilterChips extends StatelessWidget {
  final String? artist;
  final String? genre;
  final String? type;
  final ValueChanged<String?> onArtistChanged;
  final ValueChanged<String?> onGenreChanged;
  final ValueChanged<String?> onTypeChanged;
  final VoidCallback onClearAll;

  const ActiveFilterChips({
    super.key,
    required this.artist,
    required this.genre,
    required this.type,
    required this.onArtistChanged,
    required this.onGenreChanged,
    required this.onTypeChanged,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (artist != null)
            InputChip(
              label: Text(artist!),
              avatar: const Icon(Icons.person_outline, size: 18),
              onDeleted: () => onArtistChanged(null),
            ),
          if (genre != null)
            InputChip(
              label: Text(genre!),
              avatar: const Icon(Icons.category_outlined, size: 18),
              onDeleted: () => onGenreChanged(null),
            ),
          if (type != null)
            InputChip(
              label: Text(type!),
              avatar: const Icon(Icons.audio_file_outlined, size: 18),
              onDeleted: () => onTypeChanged(null),
            ),
          ActionChip(
            label: const Text('Limpar tudo'),
            avatar: const Icon(Icons.filter_alt_off, size: 18),
            onPressed: onClearAll,
          ),
        ],
      ),
    );
  }
}
