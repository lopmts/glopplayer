import 'dart:io';
import 'package:glopplayer/db/songs_db.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

class ArtworkCacheService {
  ArtworkCacheService._();
  static final ArtworkCacheService instance = ArtworkCacheService._();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  // Chave composta: "type-id", pra não confundir música com álbum/artista
  final Map<String, String?> _memCache = {};
  final Map<String, Future<String?>> _inFlight = {};

  Future<String?> getArtworkPath(int id, ArtworkType type) {
    final key = '${type.name}-$id';

    if (_memCache.containsKey(key)) {
      return Future.value(_memCache[key]);
    }
    if (_inFlight.containsKey(key)) {
      return _inFlight[key]!;
    }

    final future = _resolve(id, type, key);
    _inFlight[key] = future;
    future.whenComplete(() => _inFlight.remove(key));
    return future;
  }

  Future<String?> _resolve(int id, ArtworkType type, String key) async {
    final cachedPath = await SongsDb.getArtworkPath(key);
    if (cachedPath != null && await File(cachedPath).exists()) {
      _memCache[key] = cachedPath;
      return cachedPath;
    }

    final bytes = await _audioQuery.queryArtwork(
      id,
      type, // <- agora usa o tipo correto passado pelo chamador
      format: ArtworkFormat.JPEG,
      size: 300,
      quality: 80,
    );

    if (bytes == null || bytes.isEmpty) {
      _memCache[key] = null;
      return null;
    }

    final dir = await getTemporaryDirectory();
    final artworkDir = Directory('${dir.path}/artwork_cache');
    if (!await artworkDir.exists()) {
      await artworkDir.create(recursive: true);
    }

    // Nome de arquivo também precisa incluir o tipo, senão música e álbum
    // com mesmo id numérico sobrescrevem o arquivo um do outro
    final file = File('${artworkDir.path}/${type.name}_$id.jpg');
    await file.writeAsBytes(bytes, flush: true);
    await SongsDb.saveArtworkPath(key, file.path);

    _memCache[key] = file.path;
    return file.path;
  }

  void clearMemCache() => _memCache.clear();
}
