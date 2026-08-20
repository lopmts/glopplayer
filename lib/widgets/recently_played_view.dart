import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../services/recently_played_service.dart';
import '../widgets/artwork_thumbnail.dart';

/// Conteúdo da aba "Início" da HomeScreen: organiza o histórico de
/// reprodução em seções (músicas recentes / álbuns recentes) e oferece
/// a opção de limpar tudo.
class RecentlyPlayedView extends StatefulWidget {
  final RecentlyPlayedService recentService;
  final void Function(SongModel song) onSongTap;

  const RecentlyPlayedView({
    super.key,
    required this.recentService,
    required this.onSongTap,
  });

  @override
  State<RecentlyPlayedView> createState() => RecentlyPlayedViewState();
}

class RecentlyPlayedViewState extends State<RecentlyPlayedView> {
  late Future<List<RecentPlayEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.recentService.getRecent();
  }

  /// Exposto publicamente pra HomeScreen poder forçar um refresh
  /// (ex: depois de tocar uma música em outra aba).
  Future<void> refresh() async {
    final updated = widget.recentService.getRecent();
    setState(() => _future = updated);
    await updated;
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar histórico'),
        content: const Text(
          'Isso vai apagar toda a lista de músicas tocadas recentemente. '
          'Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.recentService.clear();
      await refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Histórico limpo')),
        );
      }
    }
  }

  /// Deriva a lista de "álbuns recentes" a partir do histórico de
  /// músicas, mantendo a ordem de reprodução mais recente e sem
  /// repetir o mesmo albumId.
  List<RecentPlayEntry> _recentAlbums(List<RecentPlayEntry> entries) {
    final seen = <int>{};
    final result = <RecentPlayEntry>[];
    for (final e in entries) {
      if (e.albumId == null) continue;
      if (seen.add(e.albumId!)) result.add(e);
      if (result.length >= 10) break;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RecentPlayEntry>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final entries = snapshot.data ?? const <RecentPlayEntry>[];

        if (entries.isEmpty) {
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              children: const [
                SizedBox(height: 120),
                Icon(Icons.history, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Nenhuma música tocada ainda.\n'
                    'As músicas que você ouvir vão aparecer aqui.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        }

        final albums = _recentAlbums(entries);

        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tocadas recentemente',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: _confirmClear,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Limpar'),
                    ),
                  ],
                ),
              ),

              // Cards horizontais de músicas recentes
              SizedBox(
                height: 190,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return _RecentSongCard(
                      entry: e,
                      onTap: () => widget.onSongTap(e.toSongModel()),
                    );
                  },
                ),
              ),

              if (albums.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    'Álbuns recentes',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(
                  height: 160,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: albums.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final e = albums[i];
                      return _RecentAlbumCard(
                        entry: e,
                        onTap: () => widget.onSongTap(e.toSongModel()),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RecentSongCard extends StatelessWidget {
  final RecentPlayEntry entry;
  final VoidCallback onTap;

  const _RecentSongCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              height: 130,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ArtworkThumbnail(
                  id: entry.songId,
                  type: ArtworkType.AUDIO,
                  borderRadius: 10,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Text(
              entry.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentAlbumCard extends StatelessWidget {
  final RecentPlayEntry entry;
  final VoidCallback onTap;

  const _RecentAlbumCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasAlbumArt = entry.albumId != null;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ArtworkThumbnail(
                  id: entry.albumId ?? entry.songId,
                  type: hasAlbumArt ? ArtworkType.ALBUM : ArtworkType.AUDIO,
                  borderRadius: 10,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              entry.album ?? 'Álbum desconhecido',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
