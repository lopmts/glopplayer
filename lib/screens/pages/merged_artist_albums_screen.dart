import 'package:flutter/material.dart';
import 'package:glopplayer/controllers/player_controller.dart';
import 'package:glopplayer/models/album_group.dart';
import 'package:glopplayer/screens/pages/player_screen.dart';
import 'package:glopplayer/services/music_library_service.dart';
import 'package:glopplayer/utils/format_utils.dart';
import 'package:glopplayer/widgets/artwork_thumbnail.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

enum _MergedSort { trackThenAlbum, title, dateAddedNewest, dateAddedOldest }

extension on _MergedSort {
  String get label {
    switch (this) {
      case _MergedSort.trackThenAlbum:
        return 'Álbum + faixa (padrão)';
      case _MergedSort.title:
        return 'Título (A-Z)';
      case _MergedSort.dateAddedNewest:
        return 'Adicionadas recentemente';
      case _MergedSort.dateAddedOldest:
        return 'Adicionadas há mais tempo';
    }
  }

  IconData get icon {
    switch (this) {
      case _MergedSort.trackThenAlbum:
        return Icons.format_list_numbered;
      case _MergedSort.title:
        return Icons.sort_by_alpha;
      case _MergedSort.dateAddedNewest:
        return Icons.new_releases_outlined;
      case _MergedSort.dateAddedOldest:
        return Icons.history;
    }
  }
}

class MergedArtistAlbumsScreen extends StatefulWidget {
  final AlbumGroup group;
  final MusicLibraryService library;

  const MergedArtistAlbumsScreen({
    super.key,
    required this.group,
    required this.library,
  });

  @override
  State<MergedArtistAlbumsScreen> createState() =>
      _MergedArtistAlbumsScreenState();
}

class _MergedArtistAlbumsScreenState extends State<MergedArtistAlbumsScreen> {
  List<SongModel> _songs = [];
  bool _loading = true;
  _MergedSort _sortBy = _MergedSort.title;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait(
      widget.group.albums.map((a) => widget.library.fetchSongsFromAlbum(a.id)),
    );
    final songs = results.expand((list) => list).toList();
    _sortSongs(songs);
    if (!mounted) return;
    setState(() {
      _songs = songs;
      _loading = false;
    });
  }

  void _sortSongs(List<SongModel> songs) {
    switch (_sortBy) {
      case _MergedSort.title:
        songs.sort((a, b) => a.title.compareTo(b.title));
        break;
      case _MergedSort.dateAddedNewest:
        songs.sort((a, b) => (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0));
        break;
      case _MergedSort.dateAddedOldest:
        songs.sort((a, b) => (a.dateAdded ?? 0).compareTo(b.dateAdded ?? 0));
        break;
      case _MergedSort.trackThenAlbum:
        songs.sort((a, b) {
          final albumCompare = (a.album ?? '').compareTo(b.album ?? '');
          if (albumCompare != 0) return albumCompare;
          return (a.track ?? 0).compareTo(b.track ?? 0);
        });
        break;
    }
  }

  void _changeSort(_MergedSort sort) {
    setState(() {
      _sortBy = sort;
      _sortSongs(_songs);
    });
  }

  void _openSortMenu() async {
    final selected = await showModalBottomSheet<_MergedSort>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Ordenar por',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            for (final sort in _MergedSort.values)
              ListTile(
                leading: Icon(sort.icon),
                title: Text(sort.label),
                trailing: _sortBy == sort
                    ? const Icon(Icons.check, color: Colors.amber)
                    : null,
                onTap: () => Navigator.pop(context, sort),
              ),
          ],
        ),
      ),
    );
    if (selected != null) _changeSort(selected);
  }

  void _openPlayer(int index) {
    // De propósito uso setPlaylist (não playAlbum): aqui não existe um
    // único AlbumModel "dono" da fila, e playAlbum guarda contexto de
    // álbum (_currentAlbum etc.) usado no auto-avanço pro próximo álbum,
    // o que não se aplica a um grupo mesclado. Se o auto-avanço disparar
    // mesmo assim, vale expor um método tipo playQueue() no
    // PlayerController que limpe esse contexto — igual foi feito pros
    // favoritos.
    context.read<PlayerController>().setPlaylist(_songs, initialIndex: index);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }

  String _formatDateAdded(SongModel song) {
    final seconds = song.dateAdded;
    if (seconds == null || seconds == 0) return 'Desconhecida';
    final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  void _showSongDetails(SongModel song) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(song.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Artista: ${song.artist ?? 'Desconhecido'}'),
            Text('Álbum: ${song.album ?? 'Desconhecido'}'),
            if (song.duration != null)
              Text(formatDuration(Duration(milliseconds: song.duration!))),
            Text('Adicionada em: ${_formatDateAdded(song)}'),
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

  @override
  Widget build(BuildContext context) {
    final group = widget.group;

    return Scaffold(
      appBar: AppBar(
        title: Text(group.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: 'Ordenar',
            onPressed: _openSortMenu,
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: _songs.isNotEmpty ? () => _openPlayer(0) : null,
            tooltip: 'Tocar todas',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: ArtworkThumbnail(
                          id: group.artworkId,
                          type: group.artworkType,
                          borderRadius: 40, // circular = "foto de artista"
                          placeholderIcon: Icons.person,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${group.albums.length} álbuns mesclados',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            Text(
                              '${_songs.length} música(s)',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.grey),
                            ),
                            Text(
                              'Ordenado por: ${_sortBy.label}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Consumer<PlayerController>(
                    builder: (context, playerController, _) {
                      return ListView.builder(
                        itemCount: _songs.length,
                        itemBuilder: (context, index) {
                          final song = _songs[index];
                          final isCurrent =
                              playerController.isCurrentSong(song);
                          final isPlaying =
                              playerController.isCurrentlyPlaying(song);

                          return ListTile(
                            tileColor: isCurrent
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.08)
                                : null,
                            leading: Opacity(
                              opacity: isCurrent ? 0.6 : 1.0,
                              child: ArtworkThumbnail(
                                width: 48,
                                height: 48,
                                id: song.id,
                                type: ArtworkType.AUDIO,
                                borderRadius: 8,
                                placeholderIcon: Icons.album,
                              ),
                            ),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                                fontWeight: isCurrent ? FontWeight.bold : null,
                              ),
                            ),
                            // Mostra de qual álbum original a faixa veio —
                            // importante numa lista mesclada de vários discos.
                            subtitle: Text(
                              song.album ?? 'Álbum desconhecido',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isPlaying)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(Icons.equalizer,
                                        size: 18, color: Colors.amber),
                                  )
                                else if (isCurrent)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(Icons.pause, size: 18),
                                  ),
                                if (song.duration != null)
                                  Text(formatDuration(
                                      Duration(milliseconds: song.duration!))),
                                IconButton(
                                  icon:
                                      const Icon(Icons.info_outline, size: 20),
                                  onPressed: () => _showSongDetails(song),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                            onTap: () => _openPlayer(index),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
