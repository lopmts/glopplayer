import 'package:flutter/material.dart';
import 'package:glopplayer/screens/pages/album_songs_screen.dart';
import 'package:glopplayer/screens/pages/merged_artist_albums_screen.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../models/album_group.dart';
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
  static const int _mergeThreshold = 5;

  final MusicLibraryService _library = MusicLibraryService();
  final TextEditingController _searchController = TextEditingController();

  List<AlbumModel> _albums = [];
  List<AlbumGroup> _allGroups = [];
  List<AlbumGroup> _filteredGroups = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _query = '';
  _SongSort _sortBy = _SongSort.track;
  bool _mergeSmallAlbums = false;

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
        _isLoading = false;
      });
      _rebuildGroups();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _rebuildGroups() {
    final groups = _mergeSmallAlbums
        ? groupAlbumsByArtist(_albums, threshold: _mergeThreshold)
        : _albums.map(AlbumGroup.single).toList();

    _sortGroups(groups);

    setState(() {
      _allGroups = groups;
    });
    _onSearchChanged(_searchController.text); // reaplica busca ativa, se houver
  }

  void _toggleMergeSmallAlbums() {
    setState(() => _mergeSmallAlbums = !_mergeSmallAlbums);
    _rebuildGroups();
  }

  /// Filtra grupos por nome do artista OU título exibido (álbum, se
  /// individual). Grupos cujo artista bate com o início da busca aparecem
  /// primeiro.
  void _onSearchChanged(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      _query = query;

      if (query.isEmpty) {
        _filteredGroups = List.of(_allGroups);
        return;
      }

      _filteredGroups = _allGroups.where((group) {
        final artistName = group.artist.toLowerCase();
        final titleMatch = group.displayTitle.toLowerCase().contains(query);
        return artistName.contains(query) || titleMatch;
      }).toList();

      _filteredGroups.sort((a, b) {
        final aStarts = a.artist.toLowerCase().startsWith(query) ? 0 : 1;
        final bStarts = b.artist.toLowerCase().startsWith(query) ? 0 : 1;
        if (aStarts != bStarts) return aStarts - bStarts;
        return a.displayTitle
            .toLowerCase()
            .compareTo(b.displayTitle.toLowerCase());
      });
    });
  }

  void _sortGroups(List<AlbumGroup> groups) {
    switch (_sortBy) {
      case _SongSort.title:
        groups.sort((a, b) => a.displayTitle.compareTo(b.displayTitle));
        break;
      case _SongSort.artist:
        groups.sort((a, b) => a.artist.compareTo(b.artist));
        break;
      case _SongSort.dateAddedNewest:
      case _SongSort.dateAddedOldest:
        groups.sort((a, b) => a.totalSongs.compareTo(b.totalSongs));
        break;
      case _SongSort.track:
        break;
    }
  }

  void _changeSort(_SongSort sort) {
    setState(() {
      _sortBy = sort;
      _sortGroups(_filteredGroups);
      _sortGroups(_allGroups);
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

  void _openGroup(AlbumGroup group) {
    if (group.isMerged) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              MergedArtistAlbumsScreen(group: group, library: _library),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AlbumSongsScreen(
            album: group.albums.first,
            library: _library,
          ),
        ),
      );
    }
  }

  Widget _buildAlbumGrid(List<AlbumGroup> groups) {
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
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return InkWell(
          key: ValueKey(group.groupKey),
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openGroup(group),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ArtworkThumbnail(
                          id: group.artworkId,
                          type: group.artworkType,
                          borderRadius: group.isMerged ? 100 : 12,
                          placeholderIcon:
                              group.isMerged ? Icons.person : Icons.album,
                        ),
                      ),
                      if (group.isMerged)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.groups,
                                size: 14, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                group.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                group.displaySubtitle,
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
            icon: Icon(
              Icons.groups,
              color: _mergeSmallAlbums
                  ? Colors.amber
                  : Theme.of(context).appBarTheme.foregroundColor,
            ),
            tooltip: _mergeSmallAlbums
                ? 'Desfazer mesclagem por artista'
                : 'Mesclar álbuns pequenos por artista',
            onPressed: _toggleMergeSmallAlbums,
          ),
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
                  if (_mergeSmallAlbums)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text(
                        'Álbuns com até $_mergeThreshold músicas do mesmo artista '
                        'foram agrupados',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                      ),
                    ),
                  if (isSearching) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        _filteredGroups.isEmpty
                            ? 'Nenhum álbum encontrado para "$_query"'
                            : 'Resultados para "$_query" (${_filteredGroups.length})',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    _buildAlbumGrid(_filteredGroups),
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
                  _buildAlbumGrid(_allGroups),
                ],
              ),
            ),
    );
  }
}
