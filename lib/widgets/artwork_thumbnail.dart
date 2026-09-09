import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../services/artwork_cache_service.dart';

class ArtworkThumbnail extends StatefulWidget {
  final int id;
  final ArtworkType type;
  final double borderRadius;
  final double? width;
  final double? height;
  final IconData placeholderIcon;
  final BoxFit fit;

  const ArtworkThumbnail({
    super.key,
    required this.id,
    required this.type,
    this.borderRadius = 8,
    this.width,
    this.height,
    this.placeholderIcon = Icons.music_note,
    this.fit = BoxFit.cover,
  });

  // ---- Cache compartilhado (LRU simples) ----------------------------
  static const int _maxCacheEntries = 200;
  static final LinkedHashMap<String, Uint8List?> _byteCache = LinkedHashMap();
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  static String _keyFor(int id, ArtworkType type) => '$type-$id';

  /// Busca os bytes da capa reaproveitando o mesmo cache usado pelos
  /// widgets `ArtworkThumbnail` na tela — evita duplicar I/O quando você
  /// precisa da mesma capa em outro lugar (ex: fundo desfocado do player).
  static Future<Uint8List?> fetchBytes(
    int id,
    ArtworkType type, {
    int quality = 95,
    int size = 400,
  }) {
    final key = _keyFor(id, type);

    if (_byteCache.containsKey(key)) {
      final bytes = _byteCache.remove(key);
      _byteCache[key] = bytes;
      return Future.value(bytes);
    }
    if (_inFlight.containsKey(key)) return _inFlight[key]!;

    final future = _fetchAndCache(id, type, key, quality: quality, size: size);
    _inFlight[key] = future;
    return future;
  }

  static Future<Uint8List?> _fetchAndCache(
    int id,
    ArtworkType type,
    String key, {
    required int quality,
    required int size,
  }) async {
    Uint8List? bytes;
    try {
      final filePath =
          await ArtworkCacheService.instance.getArtworkPath(id, type);
      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
        }
      }
      bytes ??= await OnAudioQuery().queryArtwork(
        id,
        type,
        format: ArtworkFormat.JPEG,
        size: size,
        quality: quality,
      );
    } catch (_) {
      bytes = null;
    }

    _byteCache[key] = bytes;
    if (_byteCache.length > _maxCacheEntries) {
      _byteCache.remove(_byteCache.keys.first);
    }
    _inFlight.remove(key);
    return bytes;
  }

  @override
  State<ArtworkThumbnail> createState() => _ArtworkThumbnailState();
}

class _ArtworkThumbnailState extends State<ArtworkThumbnail> {
  late Future<Uint8List?> _artworkFuture;

  @override
  void initState() {
    super.initState();
    _artworkFuture = _load();
  }

  @override
  void didUpdateWidget(covariant ArtworkThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.type != widget.type) {
      _artworkFuture = _load();
    }
  }

  Future<Uint8List?> _load() => ArtworkThumbnail.fetchBytes(
        widget.id,
        widget.type,
        size: _getArtworkSize(),
      );

  int _getArtworkSize() {
    final maxDimension = widget.width ?? widget.height ?? 400;
    if (maxDimension <= 200) return 200;
    if (maxDimension <= 400) return 400;
    if (maxDimension <= 600) return 600;
    return 800;
  }

  @override
  Widget build(BuildContext context) {
    final pixelSize = _getPixelSize();

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Container(
        width: widget.width,
        height: widget.height,
        color: _getPlaceholderColor(context),
        child: FutureBuilder<Uint8List?>(
          future: _artworkFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildPlaceholder(context, isWaiting: true);
            }
            if (snapshot.hasError) {
              return _buildPlaceholder(context, error: snapshot.error);
            }
            final bytes = snapshot.data;
            if (bytes != null && bytes.isNotEmpty) {
              return Image.memory(
                bytes,
                key: ValueKey(bytes.hashCode),
                fit: widget.fit,
                width: double.infinity,
                height: double.infinity,
                cacheWidth: pixelSize,
                cacheHeight: pixelSize,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _buildPlaceholder(context),
              );
            }
            return _buildPlaceholder(context);
          },
        ),
      ),
    );
  }

  int? _getPixelSize() {
    if (widget.width == null && widget.height == null) return null;
    final maxDimension = widget.width ?? widget.height ?? 0;
    if (maxDimension > 0) {
      return (maxDimension * MediaQuery.of(context).devicePixelRatio).round();
    }
    return null;
  }

  Widget _buildPlaceholder(
    BuildContext context, {
    bool isWaiting = false,
    Object? error,
  }) {
    return Container(
      color: _getPlaceholderColor(context),
      alignment: Alignment.center,
      child: isWaiting
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Icon(
              widget.placeholderIcon,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: _getIconSize(),
            ),
    );
  }

  Color _getPlaceholderColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.type == ArtworkType.PLAYLIST) {
      return scheme.surfaceContainerHighest.withValues(alpha: 0.7);
    }
    return scheme.surfaceContainerHighest;
  }

  double _getIconSize() {
    final maxDimension = widget.width ?? widget.height ?? 80;
    if (maxDimension <= 40) return 20;
    if (maxDimension <= 60) return 30;
    if (maxDimension <= 80) return 40;
    return 50;
  }
}
