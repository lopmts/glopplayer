import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../../controllers/player_controller.dart';
import '../artwork_thumbnail.dart';

/// Item isolado -- só rebuilda por conta própria via Selector para
/// isCurrent/isPlaying. selected/selectionMode vêm de fora porque dependem
/// do estado de seleção da lista pai.
class SongTile extends StatelessWidget {
  final SongModel song;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMoreTap;

  const SongTile({
    super.key,
    required this.song,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerController, ({bool isCurrent, bool isPlaying})>(
      selector: (_, controller) => (
        isCurrent: controller.isCurrentSong(song),
        isPlaying: controller.isCurrentlyPlaying(song),
      ),
      builder: (context, state, _) {
        return ListTile(
          selected: selected,
          selectedTileColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          leading: SizedBox(
            width: 48,
            height: 48,
            child: selectionMode
                ? Center(
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => onTap(),
                    ),
                  )
                : Opacity(
                    opacity: state.isCurrent ? 0.6 : 1.0,
                    child: ArtworkThumbnail(
                      id: song.id,
                      type: ArtworkType.AUDIO,
                      borderRadius: 6,
                    ),
                  ),
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: state.isCurrent
                  ? Theme.of(context).colorScheme.primary
                  : null,
              fontWeight: state.isCurrent ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            '${song.artist ?? "Artista desconhecido"} • ${song.album ?? "Álbum desconhecido"}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: selectionMode
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (state.isCurrent)
                      Icon(
                        state.isPlaying
                            ? Icons.volume_up
                            : Icons.pause_circle_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: onMoreTap,
                    ),
                  ],
                ),
          onTap: onTap,
          onLongPress: onLongPress,
        );
      },
    );
  }
}
