import 'package:flutter/material.dart';
import 'package:glopplayer/screens/pages/album_songs_screen.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../services/music_library_service.dart';
import '../widgets/artwork_thumbnail.dart';

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

class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  final MusicLibraryService _library = MusicLibraryService();
  final TextEditingController _searchController = TextEditingController();

  List<AlbumModel> _albums = [];
  List<AlbumModel> _filteredAlbums = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _query = '';
  _SongSort _sortBy = _SongSort.track;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
    _searchController
        .addListener(() => _onSearchChanged(_searchController.text));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAlbums() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final hasPermission = await _library.hasPermission;
      if (!hasPermission) {
        final granted = await _library.checkAndRequestPermission();
        if (!granted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Permissão negada';
          });
          return;
        }
      }

      final albums = await _library.fetchAllAlbums();
      setState(() {
        _albums = albums;
        _filteredAlbums = albums;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  /// Filtra álbuns por nome do álbum OU nome do artista.
  /// Quando o usuário digita algo que bate com o início do nome de um
  /// artista, esses álbuns aparecem primeiro (busca "de um artista
  /// específico" tem prioridade sobre correspondência parcial no título).
  void _onSearchChanged(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      _query = query;

      if (query.isEmpty) {
        _filteredAlbums = _albums;
        return;
      }

      _filteredAlbums = _albums.where((album) {
        final albumName = album.album.toLowerCase();
        final artistName = (album.artist ?? '').toLowerCase();
        return artistName.contains(query) || albumName.contains(query);
      }).toList();

      _filteredAlbums.sort((a, b) {
        final aArtist = (a.artist ?? '').toLowerCase();
        final bArtist = (b.artist ?? '').toLowerCase();
        final aStarts = aArtist.startsWith(query) ? 0 : 1;
        final bStarts = bArtist.startsWith(query) ? 0 : 1;
        if (aStarts != bStarts) return aStarts - bStarts;
        return a.album.toLowerCase().compareTo(b.album.toLowerCase());
      });
    });
  }

  void _sortAlbums(List<AlbumModel> albums) {
    switch (_sortBy) {
      case _SongSort.title:
        albums.sort((a, b) => a.album.compareTo(b.album));
        break;
      case _SongSort.artist:
        albums.sort((a, b) => (a.artist ?? '').compareTo(b.artist ?? ''));
        break;
      case _SongSort.dateAddedNewest:
      case _SongSort.dateAddedOldest:
        // Remova a ordenação por data ou implemente de outra forma
        // Por exemplo, ordenar por número de músicas como fallback
        albums.sort((a, b) => a.numOfSongs.compareTo(b.numOfSongs));
        break;
      case _SongSort.track:
        break;
    }
  }

  void _changeSort(_SongSort sort) {
    setState(() {
      _sortBy = sort;
      _sortAlbums(_filteredAlbums);
      _sortAlbums(_albums);
    });
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

  void _openAlbum(AlbumModel album) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlbumSongsScreen(album: album, library: _library),
      ),
    );
  }

  Widget _buildAlbumGrid(List<AlbumModel> albums) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openAlbum(album),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ArtworkThumbnail(
                    id: album.id,
                    type: ArtworkType.ALBUM,
                    borderRadius: 12,
                    placeholderIcon: Icons.album,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                album.album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                album.artist ?? 'Artista desconhecido',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                Text(_errorMessage!),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadAlbums,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isSearching = _query.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Álbuns'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: 'Ordenar',
            onPressed: _openSortMenu,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAlbums),
        ],
      ),
      body: _albums.isEmpty
          ? const Center(child: Text('Nenhum álbum encontrado'))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Buscar por álbum ou artista...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: _searchController.clear,
                              ),
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),

                  // Resultados da busca (quando houver uma consulta ativa)
                  if (isSearching) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        _filteredAlbums.isEmpty
                            ? 'Nenhum álbum encontrado para "$_query"'
                            : 'Resultados para "$_query" (${_filteredAlbums.length})',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    _buildAlbumGrid(_filteredAlbums),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(height: 24),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text(
                        'Todos os álbuns',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],

                  // Lista padrão (todos os álbuns), sempre visível abaixo
                  _buildAlbumGrid(_albums),
                ],
              ),
            ),
    );
  }
}
