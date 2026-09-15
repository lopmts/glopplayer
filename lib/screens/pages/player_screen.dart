import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glopplayer/services/lyrics_service.dart';
import 'package:glopplayer/widgets/speed_Button_player.dart';
import 'package:glopplayer/services/lyrics_song.dart';
import 'package:glopplayer/controllers/favorites_controller.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';

import '../../widgets/add_to_playlist_dialog.dart';
import '../../controllers/player_controller.dart';
import '../../utils/format_utils.dart';
import '../../widgets/artwork_thumbnail.dart';

/// Tela "Tocando Agora", com visual inspirado no player do Spotify:
/// - fundo em gradiente que se adapta à cor dominante da capa do álbum
/// - botão de play grande e centralizado
/// - preview de letra fixo na parte inferior
class PlayerScreen extends StatefulWidget {
  /// Callback opcional pra excluir a música atual. Se não for passado,
  /// mostra um aviso de "ainda não implementado", igual à lista.
  final Future<void> Function(SongModel song)? onDeleteSong;

  /// Fonte de letra opcional. Plugue aqui a leitura de metadados embutidos
  /// (ex: tag ID3 "USLT") ou uma API de letras. Sem isso, mostra
  /// "Letra não disponível".
  final Future<String?> Function(SongModel song)? lyricsFetcher;

  const PlayerScreen({
    super.key,
    this.onDeleteSong,
    this.lyricsFetcher,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double? _dismissDragStartY;
  double _dismissDragDistance = 0;
  // --- Loop A-B
  Duration? _pointA;
  Duration? _pointB;
  StreamSubscription<Duration>? _abSub;

  // --- Cor de fundo extraída da capa
  int? _paletteSongId;
  Color? _bgColor;
  Color? _accentColor;

  @override
  void dispose() {
    _abSub?.cancel();
    super.dispose();
  }

  void _handleAbTap(PlayerController controller) {
    setState(() {
      if (_pointA == null) {
        _pointA = controller.player.position;
      } else if (_pointB == null) {
        _pointB = controller.player.position;
        if (_pointB! <= _pointA!) {
          // B antes de A não faz sentido, ignora e mantém só A
          _pointB = null;
          return;
        }
        _abSub?.cancel();
        _abSub = controller.player.positionStream.listen((pos) {
          if (_pointA != null && _pointB != null && pos >= _pointB!) {
            controller.seek(_pointA!);
          }
        });
      } else {
        // já tinha A e B ativos -> reseta
        _abSub?.cancel();
        _abSub = null;
        _pointA = null;
        _pointB = null;
      }
    });
  }

  String get _abLabel {
    if (_pointA == null) return 'A-B';
    if (_pointB == null) return 'A…';
    return 'A-B ●';
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // NOVO — favoritar/desfavoritar a música atual. O ícone já reflete o
  // estado atual via Consumer<FavoritesController> no build(); aqui só
  // disparamos o toggle e mostramos um feedback rápido.
  Future<void> _toggleFavorite(SongModel song) async {
    final favorites = context.read<FavoritesController?>();
    if (favorites == null) return;
    final isNowFavorite = await favorites.toggle(song);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        content: Text(
          isNowFavorite ? 'Adicionada aos favoritos' : 'Removida dos favoritos',
        ),
      ),
    );
  }

  /// Extrai a cor dominante/vibrante da capa e atualiza o fundo da tela.
  /// Só reprocessa quando a música muda (evita recalcular a cada rebuild).
  Future<void> _updatePalette(int songId, Uint8List? bytes) async {
    if (_paletteSongId == songId) return;
    _paletteSongId = songId;

    if (bytes == null) {
      if (mounted) {
        setState(() {
          _bgColor = null;
          _accentColor = null;
        });
      }
      return;
    }

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        size: const Size(100, 100),
        maximumColorCount: 16,
      );

      final dominant = palette.darkMutedColor?.color ??
          palette.dominantColor?.color ??
          palette.darkVibrantColor?.color;
      final vibrant = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          dominant;

      if (!mounted) return;
      setState(() {
        _bgColor = dominant;
        _accentColor = vibrant;
      });
    } catch (_) {
      // Se a extração falhar, mantém o fallback baseado no tema.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerController>();
    final song = controller.currentSong;
    final scheme = Theme.of(context).colorScheme;

    if (song == null) {
      return const Scaffold(
        body: Center(child: Text('Nenhuma música selecionada')),
      );
    }

    return GestureDetector(
      onVerticalDragStart: (details) {
        if (details.globalPosition.dy <= 140) {
          _dismissDragStartY = details.globalPosition.dy;
          _dismissDragDistance = 0;
        } else {
          _dismissDragStartY = null;
        }
      },
      onVerticalDragUpdate: (details) {
        if (_dismissDragStartY != null && details.primaryDelta != null) {
          _dismissDragDistance += details.primaryDelta!;
        }
      },
      onVerticalDragEnd: (details) {
        final shouldDismiss = _dismissDragStartY != null &&
            (_dismissDragDistance > 56 || (details.primaryVelocity ?? 0) > 700);
        _dismissDragStartY = null;
        _dismissDragDistance = 0;
        if (shouldDismiss && mounted) {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: const Text(
            'TOCANDO AGORA',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          centerTitle: true,
          actions: [
            // NOVO — botão de favoritar. Consumer isolado pra só esse ícone
            // reconstruir quando o estado de favoritos mudar, sem rebuildar
            // a tela inteira.
            Consumer<FavoritesController?>(
              builder: (context, favorites, _) {
                final isFavorite = favorites?.isFavorite(song.id) ?? false;
                return IconButton(
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite ? Colors.redAccent : Colors.white,
                  ),
                  tooltip: isFavorite ? 'Remover dos favoritos' : 'Favoritar',
                  onPressed:
                      favorites == null ? null : () => _toggleFavorite(song),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.lyrics_outlined),
              tooltip: 'Letra',
              onPressed: () => _showLyricsSheet(context, song),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Mais opções',
              onPressed: () => _showOptionsSheet(context, song),
            ),
          ],
        ),
        body: FutureBuilder<Uint8List?>(
          future: ArtworkThumbnail.fetchBytes(song.id, ArtworkType.AUDIO),
          builder: (context, snapshot) {
            final artworkData = snapshot.data;

            if (snapshot.connectionState == ConnectionState.done) {
              // Agenda a extração de paleta pro próximo frame, pra não
              // chamar setState durante o build.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _updatePalette(song.id, artworkData);
              });
            }

            final bg = _bgColor ?? scheme.primary;
            final accent = _accentColor ?? scheme.secondary;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.55, 1.0],
                  colors: [
                    Color.lerp(bg, Colors.black, 0.10)!,
                    Color.lerp(bg, Colors.black, 0.70)!,
                    Colors.black,
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    children: [
                      const Spacer(flex: 2),

                      // Capa do álbum
                      Hero(
                        tag: 'artwork-${song.id}',
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: ArtworkThumbnail(
                              id: song.id,
                              type: ArtworkType.AUDIO,
                              borderRadius: 8,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Título + artista
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  song.artist ?? 'Artista desconhecido',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Barra de progresso
                      StreamBuilder<Duration>(
                        stream: controller.player.positionStream,
                        builder: (context, snapshot) {
                          final position = snapshot.data ?? Duration.zero;
                          final duration =
                              controller.player.duration ?? Duration.zero;
                          final maxMillis = duration.inMilliseconds > 0
                              ? duration.inMilliseconds.toDouble()
                              : 1.0;
                          final value = position.inMilliseconds
                              .clamp(0, maxMillis.toInt())
                              .toDouble();

                          return Column(
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  activeTrackColor: Colors.white,
                                  thumbColor: Colors.white,
                                  inactiveTrackColor: Colors.white24,
                                  overlayShape: SliderComponentShape.noOverlay,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 5,
                                  ),
                                ),
                                child: Slider(
                                  value: value,
                                  max: maxMillis,
                                  onChanged: (v) => controller
                                      .seek(Duration(milliseconds: v.toInt())),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(position),
                                      style: const TextStyle(
                                          color: Colors.white60, fontSize: 12),
                                    ),
                                    Text(
                                      _formatDuration(duration),
                                      style: const TextStyle(
                                          color: Colors.white60, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 4),

                      // Controles principais
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          StreamBuilder<bool>(
                            stream: controller.player.shuffleModeEnabledStream,
                            builder: (context, snapshot) {
                              final enabled = snapshot.data ?? false;
                              return IconButton(
                                iconSize: 22,
                                tooltip: 'Aleatório',
                                icon: Icon(Icons.shuffle,
                                    color: enabled ? accent : Colors.white70),
                                onPressed: () => controller.player
                                    .setShuffleModeEnabled(!enabled),
                              );
                            },
                          ),
                          IconButton(
                            iconSize: 34,
                            icon: const Icon(Icons.skip_previous,
                                color: Colors.white),
                            onPressed: controller.previous,
                          ),
                          StreamBuilder<PlayerState>(
                            stream: controller.player.playerStateStream,
                            builder: (context, snapshot) {
                              final playing = snapshot.data?.playing ?? false;
                              final processingState =
                                  snapshot.data?.processingState;

                              if (processingState == ProcessingState.loading ||
                                  processingState ==
                                      ProcessingState.buffering) {
                                return const SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: Padding(
                                    padding: EdgeInsets.all(14.0),
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  ),
                                );
                              }

                              return Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                                child: IconButton(
                                  iconSize: 32,
                                  icon: Icon(
                                    playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.black,
                                  ),
                                  onPressed: controller.playPause,
                                ),
                              );
                            },
                          ),
                          IconButton(
                            iconSize: 34,
                            icon: const Icon(Icons.skip_next,
                                color: Colors.white),
                            onPressed: controller.next,
                          ),
                          StreamBuilder<LoopMode>(
                            stream: controller.player.loopModeStream,
                            builder: (context, snapshot) {
                              final mode = snapshot.data ?? LoopMode.off;
                              final icon = mode == LoopMode.one
                                  ? Icons.repeat_one
                                  : Icons.repeat;
                              final active = mode != LoopMode.off;
                              return IconButton(
                                iconSize: 22,
                                tooltip: 'Repetir',
                                icon: Icon(icon,
                                    color: active ? accent : Colors.white70),
                                onPressed: () {
                                  final next = switch (mode) {
                                    LoopMode.off => LoopMode.all,
                                    LoopMode.all => LoopMode.one,
                                    LoopMode.one => LoopMode.off,
                                  };
                                  controller.player.setLoopMode(next);
                                },
                              );
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Controles secundários: velocidade e loop A-B
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SpeedButton(controller: controller),
                          const SizedBox(width: 16),
                          PillButton(
                            label: _abLabel,
                            active: _pointA != null,
                            icon: Icons.repeat_on_outlined,
                            onTap: () => _handleAbTap(controller),
                            onLongPress: _pointA == null
                                ? null
                                : () {
                                    setState(() {
                                      _abSub?.cancel();
                                      _abSub = null;
                                      _pointA = null;
                                      _pointB = null;
                                    });
                                  },
                          ),
                        ],
                      ),

                      const Spacer(flex: 3),

                      // Preview da letra, estilo "pill" fixo embaixo
                      LyricsPreviewBar(
                        song: song,
                        lyricsFetcher: LyricsService.instance.fetch,
                        onTap: () => _showLyricsSheet(context, song),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // --- Letra
  void _showLyricsSheet(BuildContext context, SongModel song) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => LyricsSheet(
        song: song,
        lyricsFetcher: LyricsService.instance.fetch,
      ),
    );
  }

  // --- Menu de opções
  void _showOptionsSheet(BuildContext context, SongModel song) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Adicionar à playlist'),
              onTap: () {
                Navigator.pop(sheetContext);
                showDialog(
                  context: context,
                  builder: (_) => AddToPlaylistDialog(songs: [song]),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Detalhes da música'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showSongDetails(context, song);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text(
                'Excluir',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _confirmAndDelete(context, song);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSongDetails(BuildContext context, SongModel song) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(song.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Artista: ${song.artist ?? "Desconhecido"}'),
            const SizedBox(height: 8),
            Text('Álbum: ${song.album ?? "Desconhecido"}'),
            const SizedBox(height: 8),
            Text(
                'Duração: ${formatDuration(Duration(milliseconds: song.duration ?? 0))}'),
            const SizedBox(height: 8),
            Text('Gênero: ${song.genre ?? "Desconhecido"}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDelete(BuildContext context, SongModel song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir música'),
        content: Text('Excluir "${song.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (widget.onDeleteSong == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Exclusão ainda não implementada neste app.'),
          ),
        );
      }
      return;
    }

    await widget.onDeleteSong!(song);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Música excluída')),
      );
      Navigator.of(context).pop();
    }
  }
}
