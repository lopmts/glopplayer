import 'package:on_audio_query/on_audio_query.dart';

/// Item exibido na grade de álbuns: pode ser um álbum "normal" (1 AlbumModel)
/// ou um agrupamento de vários álbuns pequenos do mesmo artista, tratado
/// como uma única entrada com a foto do artista.
class AlbumGroup {
  final String artist;
  final int? artistId;
  final List<AlbumModel> albums;

  AlbumGroup.single(AlbumModel album)
      : artist = (album.artist == null || album.artist!.trim().isEmpty)
            ? 'Artista desconhecido'
            : album.artist!,
        artistId = album.artistId,
        albums = [album];

  AlbumGroup.merged(this.artist, this.artistId, this.albums);

  bool get isMerged => albums.length > 1;

  /// Nome do artista quando mesclado, nome do álbum quando é único.
  String get displayTitle => isMerged ? artist : albums.first.album;

  String get displaySubtitle =>
      isMerged ? '${albums.length} álbuns • $totalSongs música(s)' : artist;

  int get totalSongs => albums.fold<int>(0, (sum, a) => sum + a.numOfSongs);

  /// Id do artista (foto) quando mesclado, id do álbum (capa) quando único.
  int get artworkId =>
      isMerged ? (artistId ?? albums.first.id) : albums.first.id;

  ArtworkType get artworkType =>
      isMerged ? ArtworkType.ARTIST : ArtworkType.ALBUM;

  /// Chave estável para uso em Key/ValueKey.
  String get groupKey =>
      isMerged ? 'artist-$artist' : 'album-${albums.first.id}';
}

/// Agrupa álbuns "pequenos" (<= [threshold] músicas) do mesmo artista em um
/// único AlbumGroup mesclado (foto do artista). Só mescla quando há 2+
/// álbuns pequenos do mesmo artista — um único álbum pequeno permanece
/// individual (não faz sentido "mesclar" com ele mesmo). Álbuns acima do
/// threshold nunca são mesclados, mesmo que o artista tenha vários.
List<AlbumGroup> groupAlbumsByArtist(
  List<AlbumModel> albums, {
  required int threshold,
}) {
  final Map<String, List<AlbumModel>> smallByArtist = {};
  final List<AlbumModel> individual = [];

  for (final album in albums) {
    final artistName = (album.artist ?? '').trim();
    final isSmall = album.numOfSongs <= threshold;

    if (isSmall && artistName.isNotEmpty) {
      smallByArtist.putIfAbsent(artistName, () => []).add(album);
    } else {
      individual.add(album);
    }
  }

  final List<AlbumGroup> result = [];

  smallByArtist.forEach((artistName, smallAlbums) {
    if (smallAlbums.length >= 2) {
      final artistId = smallAlbums
          .map((a) => a.artistId)
          .firstWhere((id) => id != null, orElse: () => null);
      result.add(AlbumGroup.merged(artistName, artistId, smallAlbums));
    } else {
      individual.addAll(smallAlbums); // só 1 álbum pequeno, não vale mesclar
    }
  });

  result.addAll(individual.map(AlbumGroup.single));
  return result;
}
