import 'package:flutter/material.dart';
import 'package:glopplayer/db/play_statistics_db.dart';
import 'package:glopplayer/services/app_logger.dart';
import 'package:glopplayer/widgets/artwork_thumbnail.dart';
import 'package:on_audio_query/on_audio_query.dart';

class TopPlayedBanner extends StatefulWidget {
  final void Function(SongModel song) onPlaySong;
  final void Function(SongModel song) onAddToPlaylist;

  const TopPlayedBanner({
    super.key,
    required this.onPlaySong,
    required this.onAddToPlaylist,
  });

  @override
  State<TopPlayedBanner> createState() => TopPlayedBannerState();
}

class TopPlayedBannerState extends State<TopPlayedBanner> {
  final _pageController = PageController();
  Future<List<PopularSongEntry>>? _songsFuture;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _songsFuture = PlayStatisticsDb.instance.getTopSongs();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final future = PlayStatisticsDb.instance.getTopSongs();
    setState(() {
      _songsFuture = future;
      _pageIndex = 0;
    });
    if (_pageController.hasClients) _pageController.jumpToPage(0);
    await future;
  }

  Future<void> _recordClick(SongModel song) async {
    try {
      await PlayStatisticsDb.instance.recordBannerClick(song);
      await refresh();
    } catch (error, stackTrace) {
      AppLogger.instance.e(
        'Mais ouvidas',
        'Falha ao registrar clique no destaque',
        detail: '$error\n$stackTrace',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível registrar o clique: $error'),
          ),
        );
      }
    }
  }

  Future<void> _play(PopularSongEntry entry) async {
    await _recordClick(entry.song);
    if (mounted) widget.onPlaySong(entry.song);
  }

  Future<void> _add(PopularSongEntry entry) async {
    await _recordClick(entry.song);
    if (mounted) widget.onAddToPlaylist(entry.song);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PopularSongEntry>>(
      future: _songsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Não foi possível carregar as mais ouvidas: ${snapshot.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }

        final entries = snapshot.data ?? const <PopularSongEntry>[];
        if (entries.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Mais ouvidas',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    'TOP ${entries.length}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 174,
              child: PageView.builder(
                controller: _pageController,
                itemCount: entries.length,
                onPageChanged: (index) => setState(() => _pageIndex = index),
                itemBuilder: (context, index) => _buildCard(
                  context,
                  entries[index],
                  index,
                ),
              ),
            ),
            if (entries.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    entries.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: index == _pageIndex ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: index == _pageIndex
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    PopularSongEntry entry,
    int index,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final song = entry.song;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ArtworkThumbnail(
              id: song.id,
              type: ArtworkType.AUDIO,
              borderRadius: 18,
              height: 174,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xe9000000),
                    Color(0xd9000000),
                    Color(0x77000000),
                  ],
                  stops: [0, 0.58, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      child: Text(
                        'DESTAQUE  •  #${index + 1}',
                        style: TextStyle(
                          color: scheme.onPrimary,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    song.artist?.trim().isNotEmpty == true
                        ? song.artist!.trim()
                        : 'Artista desconhecido',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.playCount} ${entry.playCount == 1 ? 'play' : 'plays'}'
                    '  •  ${entry.bannerClickCount} cliques',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => _play(entry),
                        icon: const Icon(Icons.play_arrow, size: 17),
                        label: const Text('Reproduzir'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _add(entry),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Adicionar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const Spacer(),
                    ],
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
