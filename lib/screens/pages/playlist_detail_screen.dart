import 'package:flutter/material.dart';
import 'package:glopplayer/controllers/library_controller.dart';
import 'package:glopplayer/models/playlist_models.dart';
import 'package:glopplayer/provider/playlist_provider.dart';
import 'package:glopplayer/screens/pages/metadata_editor_screen.dart';
import 'package:glopplayer/services/music_library_service.dart';
import 'package:glopplayer/widgets/add_to_playlist_dialog.dart';
import 'package:glopplayer/widgets/song_list/song_options_sheet.dart';
import 'package:glopplayer/widgets/song_list/song_selection_bar.dart';
import 'package:glopplayer/widgets/song_list/song_tile.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../../controllers/player_controller.dart';
import '../../utils/song_converter.dart';
import '../../widgets/artwork_thumbnail.dart';
import 'player_screen.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final int playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  Playlist? _playlist;
  bool _isLoading = true;
  final Set<int> _selectedSongIds = {};

  @override
  void initState() {
    super.initState();
    _loadPlaylist();
  }

  Future<void> _loadPlaylist() async {
    final provider = context.read<PlaylistProvider>();
    await provider.selectPlaylist(widget.playlistId);
    if (!mounted) return;
    setState(() {
      _playlist = provider.currentPlaylist;
      _isLoading = false;
    });
  }

  Future<void> _playSong(int index) async {
    if (_playlist == null || _playlist!.songs.isEmpty) return;

    final songs = _playlist!.songs;
    final currentIndex = await context.read<PlayerController>().playPlaylist(
          songs.map((song) => song.songId).toList(),
          initialIndex: index,
        );

    if (!mounted) return;
    if (currentIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Música não encontrada na biblioteca')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_playlist?.name ?? 'Playlist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: _playlist != null && _playlist!.songs.isNotEmpty
                ? () => _playSong(0)
                : null,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _playlist == null
              ? const Center(child: Text('Playlist não encontrada'))
              : Column(
                  children: [
                    _buildHeader(),
                    const Divider(height: 1),
                    Expanded(
                      child: _playlist!.songs.isEmpty
                          ? _buildEmptySongs()
                          : _buildSongList(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          SizedBox(width: 80, height: 80, child: _buildCoverArt()),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _playlist!.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_playlist!.songs.length} música(s)',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey[600]),
                ),
                Text(
                  'Criada em ${_formatDate(_playlist!.createdAt)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverArt() {
    if (_playlist!.coverArtId != null && _playlist!.songs.isNotEmpty) {
      return ArtworkThumbnail(
        id: _playlist!.coverArtId!,
        type: ArtworkType.AUDIO,
        borderRadius: 8,
        placeholderIcon: Icons.music_note,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.playlist_play, color: Colors.grey[600], size: 40),
    );
  }

  Widget _buildEmptySongs() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.queue_music, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Nenhuma música na playlist',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Adicione músicas a partir da biblioteca',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildSongList() {
    final songs = _playlist!.songs;
    final allSelected = songs.isNotEmpty &&
        songs.every((song) => _selectedSongIds.contains(song.songId));

    return Column(
      children: [
        if (_selectedSongIds.isNotEmpty)
          SongSelectionBar(
            selectedCount: _selectedSongIds.length,
            allSelected: allSelected,
            onClose: _clearSelection,
            onToggleSelectAll: () {
              setState(() {
                if (allSelected) {
                  _selectedSongIds.clear();
                } else {
                  _selectedSongIds.addAll(songs.map((song) => song.songId));
                }
              });
            },
            onEditMetadata: _editSelectedMetadata,
            onAddToPlaylist: _addSelectedToPlaylist,
            onDelete: _confirmRemoveSelected,
            deleteTooltip: 'Remover da playlist',
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final playlistSong = songs[index];
              final song = SongConverter.fromPlaylistSong(playlistSong);
              final selected = _selectedSongIds.contains(playlistSong.songId);
              return SongTile(
                key: ValueKey(playlistSong.songId),
                song: song,
                selected: selected,
                selectionMode: _selectedSongIds.isNotEmpty,
                onTap: () {
                  if (_selectedSongIds.isNotEmpty) {
                    _toggleSelection(playlistSong.songId);
                  } else {
                    _playSong(index);
                  }
                },
                onLongPress: () => _toggleSelection(playlistSong.songId),
                onMoreTap: () => showSongOptions(
                  context,
                  song,
                  onPlayNow: () => _playSong(index),
                  onPlayNext: () => _playNext(playlistSong),
                  onSelect: () => _toggleSelection(playlistSong.songId),
                  onAddToPlaylist: () => showDialog(
                    context: context,
                    builder: (_) => AddToPlaylistDialog(songs: [song]),
                  ),
                  onEditMetadata: () => _editMetadata(playlistSong),
                  onRemoveFromPlaylist: () => _removeSong(playlistSong),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _toggleSelection(int songId) {
    setState(() {
      if (!_selectedSongIds.add(songId)) {
        _selectedSongIds.remove(songId);
      }
    });
  }

  void _clearSelection() {
    setState(_selectedSongIds.clear);
  }

  Future<List<SongModel>> _resolveLibrarySongs(
    Iterable<PlaylistSong> playlistSongs,
  ) async {
    final librarySongs = await MusicLibraryService().fetchAllSongs();
    final songsById = {for (final song in librarySongs) song.id: song};
    return playlistSongs
        .map((song) => songsById[song.songId])
        .whereType<SongModel>()
        .toList();
  }

  Future<void> _playNext(PlaylistSong playlistSong) async {
    try {
      final songs = await _resolveLibrarySongs([playlistSong]);
      if (songs.isEmpty) {
        _showSongNotFound(playlistSong);
        return;
      }
      if (!mounted) return;
      await context.read<PlayerController>().addNextInQueue(songs.first);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${playlistSong.title} será tocada em seguida'),
          ),
        );
      }
    } catch (error) {
      _showActionError(error);
    }
  }

  Future<void> _editMetadata(PlaylistSong playlistSong) async {
    await _openMetadataEditor([playlistSong]);
  }

  Future<void> _editSelectedMetadata() async {
    final selected = _playlist!.songs
        .where((song) => _selectedSongIds.contains(song.songId))
        .toList();
    await _openMetadataEditor(selected);
  }

  Future<void> _openMetadataEditor(List<PlaylistSong> playlistSongs) async {
    try {
      final songs = await _resolveLibrarySongs(playlistSongs);
      if (!mounted) return;
      if (songs.length != playlistSongs.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Uma ou mais músicas não foram encontradas na biblioteca',
            ),
          ),
        );
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MetadataEditorScreen(
            songs: songs,
            onSaved: (_) async {
              if (!mounted) return;
              await context.read<LibraryController>().scanLibrary();
            },
          ),
        ),
      );
      if (mounted) _clearSelection();
    } catch (error) {
      _showActionError(error);
    }
  }

  Future<void> _addSelectedToPlaylist() async {
    final selected = _playlist!.songs
        .where((song) => _selectedSongIds.contains(song.songId))
        .map(SongConverter.fromPlaylistSong)
        .toList();
    if (selected.isEmpty) return;

    await showDialog(
      context: context,
      builder: (_) => AddToPlaylistDialog(songs: selected),
    );
    if (mounted) _clearSelection();
  }

  Future<void> _confirmRemoveSelected() async {
    final selected = _playlist!.songs
        .where((song) => _selectedSongIds.contains(song.songId))
        .toList();
    if (selected.isEmpty) return;

    final playlistProvider = context.read<PlaylistProvider>();
    final confirmed = await _confirmRemoval(
      selected.length == 1
          ? 'Remover "${selected.first.title}" da playlist?'
          : 'Remover ${selected.length} músicas da playlist?',
    );
    if (!confirmed || !mounted) return;

    for (final song in selected) {
      await playlistProvider.removeSongFromPlaylist(
        widget.playlistId,
        song.songId,
      );
    }
    if (!mounted) return;
    setState(() {
      _playlist = playlistProvider.currentPlaylist;
      _selectedSongIds.clear();
    });
  }

  Future<void> _removeSong(PlaylistSong song) async {
    final playlistProvider = context.read<PlaylistProvider>();
    final confirmed = await _confirmRemoval(
      'Remover "${song.title}" da playlist?',
    );
    if (!confirmed || !mounted) return;

    await playlistProvider.removeSongFromPlaylist(
      widget.playlistId,
      song.songId,
    );
    if (!mounted) return;
    setState(() {
      _playlist = playlistProvider.currentPlaylist;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Música removida da playlist')),
    );
  }

  Future<bool> _confirmRemoval(String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Remover Música'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Remover'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showSongNotFound(PlaylistSong song) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${song.title}" não foi encontrada na biblioteca'),
      ),
    );
  }

  void _showActionError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Não foi possível concluir a ação: $error')),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
