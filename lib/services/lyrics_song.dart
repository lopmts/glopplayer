import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../utils/lyrics_parser.dart';

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
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.lyricsFetcher != widget.lyricsFetcher) {
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
        final parsed = LyricsParser.parse(lyrics);
        final preview = parsed.isEmpty
            ? snapshot.hasError
                ? 'Não foi possível carregar a letra'
                : snapshot.connectionState == ConnectionState.waiting
                    ? 'Carregando letra...'
                    : 'Letra não disponível'
            : parsed.plainText
                .split('\n')
                .firstWhere(
                  (l) => l.trim().isNotEmpty,
                  orElse: () => parsed.plainText,
                )
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
  final Stream<Duration>? positionStream;
  final Duration initialPosition;
  final ValueChanged<Duration>? onSeek;

  const LyricsSheet({
    super.key,
    required this.song,
    required this.lyricsFetcher,
    this.positionStream,
    this.initialPosition = Duration.zero,
    this.onSeek,
  });

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  late Future<String?> _lyricsFuture;

  @override
  void initState() {
    super.initState();
    _lyricsFuture = _load();
  }

  @override
  void didUpdateWidget(covariant LyricsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.lyricsFetcher != widget.lyricsFetcher) {
      _lyricsFuture = _load();
    }
  }

  Future<String?> _load() {
    return widget.lyricsFetcher == null
        ? Future.value(null)
        : widget.lyricsFetcher!(widget.song);
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
            final parsed = LyricsParser.parse(lyrics);
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
                      if (!parsed.isEmpty)
                        IconButton(
                          icon: const Icon(Icons.copy_rounded),
                          tooltip: 'Copiar letra',
                          onPressed: () => _copy(parsed.plainText),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : parsed.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  snapshot.hasError
                                      ? 'Não foi possível carregar a letra.'
                                      : 'Letra não disponível para esta música.',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(color: scheme.onSurfaceVariant),
                                ),
                              ),
                            )
                          : parsed.synced
                              ? _SyncedLyricsList(
                                  parsed: parsed,
                                  controller: scrollController,
                                  positionStream: widget.positionStream,
                                  initialPosition: widget.initialPosition,
                                  onSeek: widget.onSeek,
                                )
                              : SingleChildScrollView(
                                  controller: scrollController,
                                  padding: const EdgeInsets.all(20),
                                  child: SelectableText(
                                    parsed.plainText,
                                    style:
                                        Theme.of(context).textTheme.bodyLarge,
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

class _SyncedLyricsList extends StatefulWidget {
  final ParsedLyrics parsed;
  final ScrollController controller;
  final Stream<Duration>? positionStream;
  final Duration initialPosition;
  final ValueChanged<Duration>? onSeek;

  const _SyncedLyricsList({
    required this.parsed,
    required this.controller,
    required this.positionStream,
    required this.initialPosition,
    required this.onSeek,
  });

  @override
  State<_SyncedLyricsList> createState() => _SyncedLyricsListState();
}

class _SyncedLyricsListState extends State<_SyncedLyricsList> {
  static const double _lineExtent = 72;
  int _lastActiveIndex = -1;

  void _scrollToActiveLine(int index) {
    if (index == _lastActiveIndex) return;
    _lastActiveIndex = index;
    if (index < 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.controller.hasClients) return;
      final position = widget.controller.position;
      final target =
          (index * _lineExtent - (position.viewportDimension - _lineExtent) / 2)
              .clamp(0.0, position.maxScrollExtent);
      widget.controller.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.positionStream,
      initialData: widget.initialPosition,
      builder: (context, snapshot) {
        final activeIndex = LyricsParser.activeIndex(
          widget.parsed.lines,
          snapshot.data ?? Duration.zero,
        );
        _scrollToActiveLine(activeIndex);

        final scheme = Theme.of(context).colorScheme;
        return ListView.builder(
          controller: widget.controller,
          padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 20),
          itemExtent: _lineExtent,
          itemCount: widget.parsed.lines.length,
          itemBuilder: (context, index) {
            final line = widget.parsed.lines[index];
            final active = index == activeIndex;
            return InkWell(
              onTap: widget.onSeek == null
                  ? null
                  : () => widget.onSeek!(line.time),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      color: active
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      fontSize: active ? 22 : 18,
                    ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    line.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
