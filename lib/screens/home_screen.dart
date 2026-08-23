import 'package:flutter/material.dart';
import 'package:glopplayer/main.dart';
import 'package:glopplayer/provider/playlist_provider.dart';
import 'package:glopplayer/screens/pages/favorites_screen.dart';
import 'package:glopplayer/services/song_delete_service.dart';
import 'package:glopplayer/services/recently_played_service.dart';
import 'package:glopplayer/widgets/songs_list.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:glopplayer/widgets/recently_played_view.dart';

import '../services/music_library_service.dart';
import '../services/player_controller.dart';
import 'pages/player_screen.dart';

enum _LoadState { checking, needsPermission, loadingLibrary, ready, error }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final MusicLibraryService _library = MusicLibraryService();
  final RecentlyPlayedService _recentService = RecentlyPlayedService();
  final GlobalKey<RecentlyPlayedViewState> _recentViewKey =
      GlobalKey<RecentlyPlayedViewState>();

  late final TabController _tabController;

  _LoadState _state = _LoadState.checking;
  String? _errorMessage;
  List<SongModel> _songs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkStatusOnly();
    _initPermissionFlow();
    _requestNotificationPermission();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkStatusOnly() async {
    try {
      final granted = await _library.hasPermission;
      if (!mounted) return;
      if (granted) {
        setState(() => _state = _LoadState.loadingLibrary);
        _loadLibrary();
      } else {
        setState(() => _state = _LoadState.needsPermission);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _initPermissionFlow() async {
    try {
      final granted = await _library.hasPermission;
      if (!mounted) return;

      if (granted) {
        await _loadLibrary();
        return;
      }

      // Ainda não tem permissão -> já dispara o pedido, sem esperar clique
      await _requestPermission();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _requestPermission() async {
    setState(() => _state = _LoadState.loadingLibrary);
    try {
      final granted = await _library
          .checkAndRequestPermission(retry: true)
          .timeout(const Duration(seconds: 20), onTimeout: () => false);

      if (!mounted) return;

      if (!granted) {
        setState(() => _state = _LoadState.needsPermission);
        return;
      }
      await _loadLibrary();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _errorMessage = e.toString();
      });
    }
  }

  // Pede permissão para mostrar notificações (Android 13+/iOS)
  Future<bool> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadLibrary() async {
    setState(() => _state = _LoadState.loadingLibrary);
    try {
      final results = await Future.wait([
        _library.fetchAllSongs(),
        _library.fetchAllAlbums(),
      ]).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      setState(() {
        _songs = results[0] as List<SongModel>;
        _state = _LoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _errorMessage = e.toString();
      });
    }
  }

  void _openPlayer(int index) {
    context.read<PlayerController>().setPlaylist(_songs, initialIndex: index);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    ).then((_) => _recentViewKey.currentState?.refresh());
  }

  /// Toque vindo da aba "Início" (histórico/álbuns recentes). Se a música
  /// ainda está na biblioteca carregada, toca dentro do contexto normal
  /// da fila (permite pular pra próxima/anterior). Se não estiver mais
  /// (arquivo movido, cartão SD trocado, etc.), toca sozinha usando os
  /// dados salvos no histórico.
  void _openPlayerFromSong(SongModel song) {
    final idx = _songs.indexWhere((s) => s.id == song.id);
    if (idx != -1) {
      _openPlayer(idx);
      return;
    }

    context.read<PlayerController>().setPlaylist([song], initialIndex: 0);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    ).then((_) => _recentViewKey.currentState?.refresh());
  }

  Future<void> _deleteSongs(List<SongModel> songsToDelete) async {
    bool success = false;

    try {
      success = await SongDeleteService.deleteSongs(
        songsToDelete.map((s) => s.id).toList(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $e')),
        );
      }
      return;
    }

    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Exclusão cancelada ou não concluída.'),
          ),
        );
      }
      return;
    }

    final deletedIds = songsToDelete.map((s) => s.id).toSet();

    final playlistProvider = context.read<PlaylistProvider>();
    for (final id in deletedIds) {
      await playlistProvider.removeSongFromAllPlaylists(id);
    }

    if (!mounted) return;
    setState(() {
      _songs.removeWhere((s) => deletedIds.contains(s.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _LoadState.checking:
      case _LoadState.loadingLibrary:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );

      case _LoadState.error:
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 64, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  Text(
                    'Não foi possível carregar a biblioteca.\n${_errorMessage ?? ""}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _checkStatusOnly,
                    child: const Text('Tentar de novo'),
                  ),
                ],
              ),
            ),
          ),
        );

      case _LoadState.needsPermission:
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Precisamos de permissão para acessar as músicas do aparelho.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _requestPermission,
                    child: const Text('Conceder permissão'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => openAppSettings(),
                    child: const Text('Abrir configurações do app'),
                  ),
                ],
              ),
            ),
          ),
        );

      case _LoadState.ready:
        return Scaffold(
          appBar: AppBar(
            title: const Text('GlopPlayer'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadLibrary,
                tooltip: 'Atualizar biblioteca',
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.home_outlined), text: 'Início'),
                Tab(icon: Icon(Icons.library_music_outlined), text: 'Músicas'),
                Tab(
                    icon: Icon(Icons.favorite_outlined),
                    text: 'Favoritas'), // Add this
              ],
            ),
          ),
          // TabBarView já entrega o "arrastar pro lado" de graça — o
          // usuário troca de aba tanto pelo toque quanto pelo swipe.
          body: TabBarView(
            controller: _tabController,
            children: [
              RecentlyPlayedView(
                key: _recentViewKey,
                recentService: _recentService,
                onSongTap: _openPlayerFromSong,
              ),
              MusicListItems(
                songs: _songs,
                onSongTap: _openPlayer,
                onDeleteSongs: _deleteSongs,
              ),
              FavoritesScreen(
                onSongTap: (song) {
                  // Get the controller from context
                  context.read<PlayerController>().playSong(song);
                },
              ),
            ],
          ),
        );
    }
  }
}
