import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:glopplayer/screens/pages/player_screen.dart';
import 'package:glopplayer/services/music_library_service.dart';
import 'package:glopplayer/controllers/player_controller.dart';
import 'package:glopplayer/utils/format_utils.dart';
import 'package:glopplayer/widgets/artwork_thumbnail.dart';
import 'package:glopplayer/widgets/mini_player_bar.dart';
import 'package:glopplayer/services/additional_settings_service.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

enum _SongSort {
  track,
  title,
  artist,
  dateAddedNewest,
  dateAddedOldest,
}

extension on _SongSort {
  String get label {
    switch (this) {
      case _SongSort.track:
        return 'Faixa (padrão)';
      case _SongSort.title:
        return 'Título (A-Z)';
      case _SongSort.artist:
        return 'Artista (A-Z)';
      case _SongSort.dateAddedNewest:
        return 'Adicionadas recentemente';
      case _SongSort.dateAddedOldest:
        return 'Adicionadas há mais tempo';
    }
  }

  IconData get icon {
    switch (this) {
      case _SongSort.track:
        return Icons.format_list_numbered;
      case _SongSort.title:
        return Icons.sort_by_alpha;
      case _SongSort.artist:
        return Icons.person_outline;
      case _SongSort.dateAddedNewest:
        return Icons.new_releases_outlined;
      case _SongSort.dateAddedOldest:
        return Icons.history;
    }
  }
}

class AlbumSongsScreen extends StatefulWidget {
  final AlbumModel album;
  final MusicLibraryService library;

  const AlbumSongsScreen({
    super.key,
    required this.album,
    required this.library,
  });

  @override
  State<AlbumSongsScreen> createState() => _AlbumSongsScreenState();
}

class _AlbumSongsScreenState extends State<AlbumSongsScreen> {
  List<SongModel> _songs = [];
  bool _loading = true;
  _SongSort _sortBy = _SongSort.track;

  StreamSubscription<void>? _playlistCompletedSub;
  bool _autoAdvanceHandled = false; // evita disparar 2x pro mesmo fim

  @override
  void initState() {
    super.initState();
    _load();

    // O listener é registrado uma vez só — não depende de rebuild
    final pc = context.read<PlayerController>();
    _playlistCompletedSub = pc.playlistCompleted.listen((_) {
      _handlePlaylistCompleted(pc);
    });
  }

  @override
  void dispose() {
    _playlistCompletedSub?.cancel();
    super.dispose();
  }

  void _handlePlaylistCompleted(PlayerController pc) {
    if (_autoAdvanceHandled || _songs.isEmpty) return;

    // Só reage se a playlist que terminou é a deste álbum (evita
    // disparar caso o usuário tenha trocado pra outro álbum/playlist
    // nesse meio-tempo, já que o PlayerController é global)
    final currentIds = pc.playlist.map((s) => s.id).toList();
    final thisAlbumIds = _songs.map((s) => s.id).toList();
    if (!listEquals(currentIds, thisAlbumIds)) return;

    // Confirma que estava mesmo na última faixa
    if (pc.currentIndex != _songs.length - 1) return;

    _autoAdvanceHandled = true;
    _autoAdvanceToNextAlbum(pc);
  }

  Future<void> _autoAdvanceToNextAlbum(PlayerController pc) async {
    final albums = await widget.library.fetchAllAlbums();
    final currentAlbumIndex = albums.indexWhere((a) => a.id == widget.album.id);

    if (currentAlbumIndex == -1 || currentAlbumIndex + 1 >= albums.length) {
      return; // era o último álbum da lista, não faz nada
    }

    final nextAlbum = albums[currentAlbumIndex + 1];
    final nextSongs = await widget.library.fetchSongsFromAlbum(nextAlbum.id);
    if (nextSongs.isEmpty) return;

    if (!mounted) return;
    await pc.setPlaylist(nextSongs, initialIndex: 0);
  }

  Future<void> _load() async {
    var songs = await widget.library.fetchSongsFromAlbum(widget.album.id);
    _sortSongs(songs);
    setState(() {
      _songs = songs;
      _loading = false;
    });
  }

  void _sortSongs(List<SongModel> songs) {
    switch (_sortBy) {
      case _SongSort.title:
        songs.sort((a, b) => a.title.compareTo(b.title));
        break;
      case _SongSort.artist:
        songs.sort((a, b) => (a.artist ?? '').compareTo(b.artist ?? ''));
        break;
      case _SongSort.dateAddedNewest:
        songs.sort((a, b) => (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0));
        break;
      case _SongSort.dateAddedOldest:
        songs.sort((a, b) => (a.dateAdded ?? 0).compareTo(b.dateAdded ?? 0));
        break;
      case _SongSort.track:
        songs.sort((a, b) => (a.track ?? 0).compareTo(b.track ?? 0));
        break;
    }
  }

  void _changeSort(_SongSort sort) {
    setState(() {
      _sortBy = sort;
      _sortSongs(_songs);
    });
  }

  void _openPlayer(int index) {
    context.read<PlayerController>().playAlbum(
          widget.album,
          _songs,
          initialIndex: index,
        );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  void _showSongOptions(SongModel song, int index) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Tocar agora'),
              onTap: () {
                Navigator.pop(context);
                _openPlayer(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: const Text('Tocar em seguida'),
              onTap: () async {
                Navigator.pop(context);
                final controller = context.read<PlayerController>();
                await controller.addNextInQueue(song);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${song.title} será tocada em seguida'),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Adicionar à playlist'),
              onTap: () {
                Navigator.pop(context);
                _addToPlaylist(song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Detalhes'),
              onTap: () {
                Navigator.pop(context);
                _showSongDetails(song);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _addToPlaylist(SongModel song) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${song.title} adicionado à playlist')),
    );
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
            Text('Tamanho: ${song.size ?? 'Desconhecido'}'),
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

  void _openSortMenu() async {
    final selected = await showModalBottomSheet<_SongSort>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Ordenar por',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            for (final sort in _SongSort.values)
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

    if (selected != null) {
      _changeSort(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album.album,
            maxLines: 1, overflow: TextOverflow.ellipsis),
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
      bottomNavigationBar:
          context.watch<AdditionalSettingsService>().showPlayerOnAlbums
              ? const MiniPlayerBar()
              : null,
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
                          id: widget.album.id,
                          type: ArtworkType.ALBUM,
                          borderRadius: 8,
                          placeholderIcon: Icons.album,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.album.artist ?? 'Artista desconhecido',
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
                          final showDate =
                              _sortBy == _SongSort.dateAddedNewest ||
                                  _sortBy == _SongSort.dateAddedOldest;

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
                            subtitle: Text(
                              showDate
                                  ? '${song.artist ?? "Artista desconhecido"} • ${_formatDateAdded(song)}'
                                  : song.artist ?? 'Artista desconhecido',
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
                                  icon: const Icon(Icons.more_vert, size: 20),
                                  onPressed: () =>
                                      _showSongOptions(song, index),
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
