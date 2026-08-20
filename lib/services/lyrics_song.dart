import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

class LyricsPreviewBar extends StatefulWidget {
  final SongModel song;
  final Future<String?> Function(SongModel song)? lyricsFetcher;
  final VoidCallback onTap;

  const LyricsPreviewBar({
    super.key,
    required this.song,
    required this.lyricsFetcher,
    required this.onTap,
  });

  @override
  State<LyricsPreviewBar> createState() => _LyricsPreviewBarState();
}

class _LyricsPreviewBarState extends State<LyricsPreviewBar> {
  late Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant LyricsPreviewBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _future = _load();
    }
  }

  Future<String?> _load() {
    return widget.lyricsFetcher != null
        ? widget.lyricsFetcher!(widget.song)
        : Future.value(null);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snapshot) {
        final lyrics = snapshot.data;
        final preview = (lyrics == null || lyrics.trim().isEmpty)
            ? 'Letra não disponível'
            : lyrics
                .split('\n')
                .firstWhere((l) => l.trim().isNotEmpty, orElse: () => lyrics)
                .trim();

        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.lyrics_outlined,
                    size: 18, color: Colors.white70),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: Colors.white54),
              ],
            ),
          ),
        );
      },
    );
  }
}

class LyricsSheet extends StatefulWidget {
  final SongModel song;
  final Future<String?> Function(SongModel song)? lyricsFetcher;

  const LyricsSheet(
      {super.key, required this.song, required this.lyricsFetcher});

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  late Future<String?> _lyricsFuture;

  @override
  void initState() {
    super.initState();
    _lyricsFuture = widget.lyricsFetcher != null
        ? widget.lyricsFetcher!(widget.song)
        : Future.value(null);
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Letra copiada')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return FutureBuilder<String?>(
          future: _lyricsFuture,
          builder: (context, snapshot) {
            final lyrics = snapshot.data;
            final loading = snapshot.connectionState == ConnectionState.waiting;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(right: 12),
                      ),
                      Expanded(
                        child: Text(
                          'Letra',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (lyrics != null && lyrics.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.copy_rounded),
                          tooltip: 'Copiar letra',
                          onPressed: () => _copy(lyrics),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : (lyrics == null || lyrics.isEmpty)
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Letra não disponível para esta música.',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(color: scheme.onSurfaceVariant),
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                              controller: scrollController,
                              padding: const EdgeInsets.all(20),
                              child: SelectableText(
                                lyrics,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
