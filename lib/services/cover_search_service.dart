import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class CoverSearchResult {
  final String artworkUrlSmall;
  final String artworkUrlHigh;
  final String collectionName;
  final String artistName;

  const CoverSearchResult({
    required this.artworkUrlSmall,
    required this.artworkUrlHigh,
    required this.collectionName,
    required this.artistName,
  });
}

/// Busca capas de álbum usando a API pública do iTunes Search — não exige
/// chave/token. Cobre bem lançamentos comerciais; artistas independentes ou
/// muito nichados podem não aparecer nos resultados.
class CoverSearchService {
  CoverSearchService._();

  static Future<List<CoverSearchResult>> search({
    required String query,
    int limit = 16,
  }) async {
    if (query.trim().isEmpty) return const [];

    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': query,
      'entity': 'album',
      'limit': '$limit',
    });

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (body['results'] as List<dynamic>? ?? []);

      return results
          .map((raw) {
            final map = raw as Map<String, dynamic>;
            final small = map['artworkUrl100'] as String? ?? '';
            if (small.isEmpty) return null;
            final high = small.replaceAll('100x100bb', '1200x1200bb');
            return CoverSearchResult(
              artworkUrlSmall: small,
              artworkUrlHigh: high,
              collectionName: map['collectionName'] as String? ?? '',
              artistName: map['artistName'] as String? ?? '',
            );
          })
          .whereType<CoverSearchResult>()
          .toList();
    } catch (e) {
      // sem internet, timeout, JSON malformado etc — nunca deixa isso
      // vazar pra quem chamou, senão o loading trava pra sempre
      return const [];
    }
  }

  static Future<Uint8List> downloadBytes(String url) async {
    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Falha ao baixar imagem: HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }
}
