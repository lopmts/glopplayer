import 'package:flutter/material.dart';
import 'package:glopplayer/widgets/artwork_thumbnail.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../screens/pages/player_screen.dart';
import '../services/player_controller.dart';

/// Barra fixa mostrando a música atual, com progresso e controles rápidos.
/// Deve ficar no "shell" persistente do app (ex: MainTabScreen), acima da
/// bottom nav bar — assim ela some sozinha quando qualquer tela é empurrada
/// por cima (como a PlayerScreen), sem precisar checar rota manualmente.
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerController>();
    final song = controller.currentSong;

    // Sem música carregada -> não ocupa espaço nenhum.
    if (song == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PlayerScreen()),
      ),
      child: Material(
        color: cs.surfaceContainerHigh,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MiniProgressBar(controller: controller),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: ArtworkThumbnail(
                      id: song.id,
                      type: ArtworkType.AUDIO,
                      borderRadius: 8,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          song.artist ?? 'Artista desconhecido',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      controller.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: cs.primary,
                    ),
                    iconSize: 36,
                    onPressed: controller.playPause,
                    tooltip: controller.isPlaying ? 'Pausar' : 'Tocar',
                  ),
                  IconButton(
                    icon: Icon(Icons.skip_next, color: cs.onSurface),
                    onPressed: controller.next,
                    tooltip: 'Próxima',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Linha fina de progresso no topo da barra (estilo Spotify).
class _MiniProgressBar extends StatelessWidget {
  final PlayerController controller;
  const _MiniProgressBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<Duration>(
      stream: controller.player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = controller.player.duration ?? Duration.zero;
        final progress = duration.inMilliseconds > 0
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0;

        return SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(cs.primary),
          ),
        );
      },
    );
  }
}
