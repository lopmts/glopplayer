import 'dart:async';

import 'package:flutter/material.dart';
import 'package:glopplayer/screens/pages/metadata_editor_screen.dart';
import 'package:glopplayer/widgets/add_to_playlist_dialog.dart';
import 'package:glopplayer/controllers/library_controller.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../controllers/player_controller.dart';
import '../screens/pages/player_screen.dart';
import 'song_list/song_filter_engine.dart';
import 'song_list/song_tile.dart';
import 'song_list/song_selection_bar.dart';
import 'song_list/song_filter_sheet.dart';
import 'song_list/song_options_sheet.dart';
import 'song_list/active_filter_chips.dart';

class MusicListItems extends StatefulWidget {
  final List<SongModel> songs;
  final Function(int index)? onSongTap;

  /// Callback para excluir as músicas selecionadas. Se não for passado,
  /// o widget só avisa via SnackBar que a função não está pronta.
  final Future<void> Function(List<SongModel> songs)? onDeleteSongs;

  const MusicListItems({
    super.key,
    required this.songs,
    this.onSongTap,
    this.onDeleteSongs,
  });

  @override
  State<MusicListItems> createState() => _MusicListScreenState();
}

class _MusicListScreenState extends State<MusicListItems> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SongFilterEngine _filterEngine = SongFilterEngine();
  Timer? _debounce;

  static const int _pageSize = 50;
  static const double _itemHeight = 72;
  int _visibleCount = _pageSize;

  final Set<int> _selectedIds = {};
  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      final folders = context.read<LibraryController>().folders;
      final total = _filterEngine.filteredSongs(widget.songs, folders).length;
      if (_visibleCount < total) {
        setState(() {
          _visibleCount = (_visibleCount + _pageSize).clamp(0, total);
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _filterEngine.query = value;
        _visibleCount = _pageSize;
      });
    });
  }

  void _applyFilters({String? artist, String? genre, String? type}) {
    setState(() {
      _filterEngine.artistFilter = artist;
      _filterEngine.genreFilter = genre;
      _filterEngine.typeFilter = type;
      _visibleCount = _pageSize;
    });
  }

  void _clearFilters() {
    if (!_filterEngine.hasActiveFilter) return;
    setState(() {
      _filterEngine.clear();
      _visibleCount = _pageSize;
    });
  }

  // Toca a partir da lista JÁ FILTRADA -- com filtro de artista/gênero/tipo
  // ou busca ativos, a fila de reprodução vira exatamente aquele
  // subconjunto, não a biblioteca inteira.
  void _playSong(BuildContext context, List<SongModel> songs, int index) {
    if (widget.onSongTap != null) {
      widget.onSongTap!(index);
      return;
    }
    context.read<PlayerController>().setPlaylist(songs, initialIndex: index);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  void _toggleSelected(SongModel song) {
    setState(() {
      if (_selectedIds.contains(song.id)) {
        _selectedIds.remove(song.id);
      } else {
        _selectedIds.add(song.id);
      }
    });
  }

  void _enterSelectionWith(SongModel song) {
    setState(() => _selectedIds.add(song.id));
  }

  void _clearSelection() {
    setState(() => _selectedIds.clear());
  }

  void _selectAll(List<SongModel> songs) {
    setState(() => _selectedIds.addAll(songs.map((s) => s.id)));
  }

  bool _isAllSelected(List<SongModel> songs) =>
      songs.isNotEmpty && songs.every((s) => _selectedIds.contains(s.id));

  List<SongModel> _selectedSongs() {
    // Usa widget.songs como fonte "master" pra não perder seleção que
    // eventualmente saiu do filtro atual (busca/pasta mudou no meio do caminho).
    return widget.songs.where((s) => _selectedIds.contains(s.id)).toList();
  }

  Future<void> _confirmAndDelete() async {
    final selected = _selectedSongs();
    if (selected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir músicas'),
        content: Text(
          selected.length == 1
              ? 'Excluir "${selected.first.title}"?'
              : 'Excluir ${selected.length} músicas selecionadas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (widget.onDeleteSongs == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Exclusão ainda não implementada neste app.'),
          ),
        );
      }
      return;
    }

    await widget.onDeleteSongs!(selected);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selected.length == 1
                ? 'Música excluída'
                : '${selected.length} músicas excluídas',
          ),
        ),
      );
      _clearSelection();
    }
  }

  Future<void> _addSelectedToPlaylist() async {
    final selected = _selectedSongs();
    if (selected.isEmpty) return;

    await showDialog(
      context: context,
      builder: (_) => AddToPlaylistDialog(songs: selected),
    );

    _clearSelection();
  }

  Future<void> _openMetadataEditor(List<SongModel> songs) async {
    if (songs.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MetadataEditorScreen(
          songs: songs,
          onSaved: (savedSongs) async {
            await context.read<LibraryController>().scanLibrary();
          },
        ),
      ),
    );

    if (mounted && _selectionMode) {
      _clearSelection();
    }
  }

  Future<void> _showFilterSheet(List<String> folders) async {
    await showSongFilterSheet(
      context,
      artists: _filterEngine.availableArtists(widget.songs, folders),
      genres: _filterEngine.availableGenres(widget.songs, folders),
      types: _filterEngine.availableTypes(widget.songs, folders),
      currentArtist: _filterEngine.artistFilter,
      currentGenre: _filterEngine.genreFilter,
      currentType: _filterEngine.typeFilter,
      onApply: (artist, genre, type) =>
          _applyFilters(artist: artist, genre: genre, type: type),
    );
  }

  @override
  Widget build(BuildContext context) {
    final folders = context.watch<LibraryController>().folders;
    final filtered = _filterEngine.filteredSongs(widget.songs, folders);
    final visible = filtered.take(_visibleCount).toList();

    return Column(
      children: [
        _selectionMode
            ? SongSelectionBar(
                selectedCount: _selectedIds.length,
                allSelected: _isAllSelected(filtered),
                onClose: _clearSelection,
                onToggleSelectAll: () => _isAllSelected(filtered)
                    ? _clearSelection()
                    : _selectAll(filtered),
                onEditMetadata: () => _openMetadataEditor(_selectedSongs()),
                onAddToPlaylist: _addSelectedToPlaylist,
                onDelete: _confirmAndDelete,
              )
            : _buildSearchBar(folders),
        if (!_selectionMode && _filterEngine.hasActiveFilter)
          ActiveFilterChips(
            artist: _filterEngine.artistFilter,
            genre: _filterEngine.genreFilter,
            type: _filterEngine.typeFilter,
            onArtistChanged: (v) => _applyFilters(
              artist: v,
              genre: _filterEngine.genreFilter,
              type: _filterEngine.typeFilter,
            ),
            onGenreChanged: (v) => _applyFilters(
              artist: _filterEngine.artistFilter,
              genre: v,
              type: _filterEngine.typeFilter,
            ),
            onTypeChanged: (v) => _applyFilters(
              artist: _filterEngine.artistFilter,
              genre: _filterEngine.genreFilter,
              type: v,
            ),
            onClearAll: _clearFilters,
          ),
        Expanded(
          child: widget.songs.isEmpty
              ? const Center(
                  child: Text('Nenhuma música encontrada no aparelho'))
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        _filterEngine.query.isEmpty &&
                                !_filterEngine.hasActiveFilter
                            ? 'Nenhuma música nas pastas selecionadas'
                            : 'Nenhum resultado para esse filtro/busca',
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: false,
                      cacheExtent: 500,
                      itemExtent: _itemHeight,
                      itemCount: visible.length +
                          (visible.length < filtered.length ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= visible.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final song = visible[index];
                        final isSelected = _selectedIds.contains(song.id);
                        return RepaintBoundary(
                          key: ValueKey(song.id),
                          child: SongTile(
                            song: song,
                            selected: isSelected,
                            selectionMode: _selectionMode,
                            onTap: () {
                              if (_selectionMode) {
                                _toggleSelected(song);
                              } else {
                                // index é relativo a `filtered` -- `visible` é
                                // só o prefixo paginado dela, então a fila
                                // final continua sendo o que foi filtrado.
                                _playSong(context, filtered, index);
                              }
                            },
                            onLongPress: () {
                              if (!_selectionMode) _enterSelectionWith(song);
                            },
                            onMoreTap: () => showSongOptions(
                              context,
                              song,
                              onPlayNow: () => _playSong(context, [song], 0),
                              onPlayNext: () async {
                                await context
                                    .read<PlayerController>()
                                    .addNextInQueue(song);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${song.title} será tocada em seguida'),
                                    ),
                                  );
                                }
                              },
                              onSelect: () => _enterSelectionWith(song),
                              onAddToPlaylist: () => showDialog(
                                context: context,
                                builder: (_) =>
                                    AddToPlaylistDialog(songs: [song]),
                              ),
                              onEditMetadata: () => _openMetadataEditor([song]),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(List<String> folders) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Buscar música ou artista...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _filterEngine.query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
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
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: _filterEngine.hasActiveFilter,
            smallSize: 8,
            child: IconButton.filledTonal(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filtrar por artista/gênero/tipo',
              onPressed: () => _showFilterSheet(folders),
            ),
          ),
        ],
      ),
    );
  }
}
