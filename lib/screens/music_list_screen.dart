import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import 'package:glopplayer/widgets/songs_list.dart';
import '../services/music_library_service.dart';
import '../controllers/player_controller.dart';

class MusicListScreen extends StatefulWidget {
  const MusicListScreen({super.key});

  @override
  State<MusicListScreen> createState() => _MusicListScreenState();
}

class _MusicListScreenState extends State<MusicListScreen> {
  final MusicLibraryService _library = MusicLibraryService();
  List<SongModel> _songs = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Verifica permissão
      final hasPermission = await _library.hasPermission;
      if (!hasPermission) {
        final granted = await _library.checkAndRequestPermission();
        if (!granted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Permissão negada para acessar as músicas';
          });
          return;
        }
      }

      // Carrega as músicas
      final songs = await _library.fetchAllSongs();
      setState(() {
        _songs = songs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _playSong(int index) {
    final controller = context.read<PlayerController>();
    controller.setPlaylist(_songs, initialIndex: index);
    Navigator.pushNamed(context, '/player');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadSongs,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Todas as Músicas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSongs,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _songs.isEmpty
          ? const Center(
              child: Text('Nenhuma música encontrada'),
            )
          : MusicListItems(
              songs: _songs,
              onSongTap: _playSong,
            ),
    );
  }
}
