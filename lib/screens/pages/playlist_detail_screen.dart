import 'package:flutter/material.dart';
import 'package:glopplayer/models/playlist_models.dart';
import 'package:glopplayer/provider/playlist_provider.dart';
import 'package:glopplayer/utils/song_converter.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../widgets/artwork_thumbnail.dart';
import '../../services/player_controller.dart';
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

  @override
  void initState() {
    super.initState();
    _loadPlaylist();
  }

  Future<void> _loadPlaylist() async {
    final provider = context.read<PlaylistProvider>();
    await provider.selectPlaylist(widget.playlistId);
    setState(() {
      _playlist = provider.currentPlaylist;
      _isLoading = false;
    });
  }

  void _playSong(int index) {
    if (_playlist == null || _playlist!.songs.isEmpty) return;

    final songs = SongConverter.fromPlaylistSongs(_playlist!.songs);

    context.read<PlayerController>().setPlaylist(songs, initialIndex: index);
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
          SizedBox(
            width: 80,
            height: 80,
            child: _buildCoverArt(),
          ),
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                Text(
                  'Criada em ${_formatDate(_playlist!.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[500],
                      ),
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
      child: Icon(
        Icons.playlist_play,
        color: Colors.grey[600],
        size: 40,
      ),
    );
  }

  Widget _buildEmptySongs() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.queue_music,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma música na playlist',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Adicione músicas a partir da biblioteca',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _playlist!.songs.length,
      itemBuilder: (context, index) {
        final song = _playlist!.songs[index];
        return ListTile(
          leading: CircleAvatar(
            child: Text('${index + 1}'),
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            song.artist ?? 'Artista desconhecido',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
            onPressed: () => _removeSong(context, song),
          ),
          onTap: () => _playSong(index),
        );
      },
    );
  }

  void _removeSong(BuildContext context, PlaylistSong song) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remover Música'),
        content: Text('Remover "${song.title}" da playlist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<PlaylistProvider>().removeSongFromPlaylist(
                    widget.playlistId,
                    song.songId,
                  );
              setState(() {
                _playlist = context.read<PlaylistProvider>().currentPlaylist;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Música removida da playlist')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
