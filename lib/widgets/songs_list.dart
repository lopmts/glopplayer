import 'dart:async';

import 'package:flutter/material.dart';
import 'package:glopplayer/widgets/add_to_playlist_dialog.dart';
import 'package:glopplayer/controllers/library_controller.dart';
import 'package:glopplayer/utils/format_utils.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../services/player_controller.dart';
import 'artwork_thumbnail.dart';
import '../screens/pages/player_screen.dart';

class MusicListItems extends StatefulWidget {
  final List<SongModel> songs;
  final Function(int index)? onSongTap;

  /// Callback para excluir as músicas selecionadas. Ainda não existe
  /// implementação real disso no projeto — se não for passado, o widget
  /// só avisa via SnackBar que a função não está pronta.
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
  Timer? _debounce;

  static const int _pageSize = 50;
  static const double _itemHeight = 72;
  int _visibleCount = _pageSize;
  String _query = '';

  // --- Seleção múltipla -----------------------------------------------
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
      final total = _filteredSongs(folders).length;
      if (_visibleCount < total) {
        setState(() {
          _visibleCount = (_visibleCount + _pageSize).clamp(0, total);
        });
      }
    }
  }

  bool _isInsideAnyFolder(String filePath, List<String> folders) {
    if (folders.isEmpty) return true;
    final normalizedFile = filePath.toLowerCase();
    for (final folder in folders) {
      var normalizedFolder = folder.toLowerCase();
      if (!normalizedFolder.endsWith('/')) {
        normalizedFolder = '$normalizedFolder/';
      }
      if (normalizedFile.startsWith(normalizedFolder)) return true;
    }
    return false;
  }

  List<SongModel> _filteredSongs(List<String> folders) {
    Iterable<SongModel> base = widget.songs;

    if (folders.isNotEmpty) {
      base = base.where((song) => _isInsideAnyFolder(song.data, folders));
    }

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      base = base.where((song) {
        final title = song.title.toLowerCase();
        final artist = (song.artist ?? '').toLowerCase();
        return title.contains(q) || artist.contains(q);
      });
    }

    return base.toList();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _query = value;
        _visibleCount = _pageSize;
      });
    });
  }

  void _playSong(BuildContext context, List<SongModel> songs, int index) {
    if (widget.onSongTap != null) {
      widget.onSongTap!(index);
      return;
    }
    debugPrint(
        'TAP: index=$index, song=${songs[index].title}, id=${songs[index].id}, path=${songs[index].data}');
    context.read<PlayerController>().setPlaylist(songs, initialIndex: index);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  // --- Helpers de seleção -----------------------------------------------

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

  List<SongModel> _selectedSongs(List<SongModel> allFiltered) {
    // Usa widget.songs como fonte "master" pra não perder seleção que
    // eventualmente saiu do filtro atual (busca/pasta mudou no meio do caminho).
    return widget.songs.where((s) => _selectedIds.contains(s.id)).toList();
  }

  Future<void> _confirmAndDelete(List<SongModel> allFiltered) async {
    final selected = _selectedSongs(allFiltered);
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

  Future<void> _addSelectedToPlaylist(List<SongModel> allFiltered) async {
    final selected = _selectedSongs(allFiltered);
    if (selected.isEmpty) return;

    await showDialog(
      context: context,
      builder: (_) => AddToPlaylistDialog(songs: selected),
    );

    _clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final folders = context.watch<LibraryController>().folders;
    final filtered = _filteredSongs(folders);
    final visible = filtered.take(_visibleCount).toList();

    return Column(
      children: [
        _selectionMode ? _buildSelectionBar(filtered) : _buildSearchBar(),
        Expanded(
          child: widget.songs.isEmpty
              ? const Center(
                  child: Text('Nenhuma música encontrada no aparelho'))
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        _query.isEmpty
                            ? 'Nenhuma música nas pastas selecionadas'
                            : 'Nenhum resultado para essa busca',
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
                          child: _SongTile(
                            song: song,
                            selected: isSelected,
                            selectionMode: _selectionMode,
                            onTap: () {
                              if (_selectionMode) {
                                _toggleSelected(song);
                              } else {
                                _playSong(context, filtered, index);
                              }
                            },
                            onLongPress: () {
                              if (!_selectionMode) {
                                _enterSelectionWith(song);
                              }
                            },
                            onMoreTap: () => _showSongOptions(context, song),
                            key: null,
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Buscar música ou artista...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.isEmpty
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
    );
  }

  Widget _buildSelectionBar(List<SongModel> filtered) {
    final allSelected = _isAllSelected(filtered);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancelar seleção',
              onPressed: _clearSelection,
            ),
            Expanded(
              child: Text(
                '${_selectedIds.length} selecionada${_selectedIds.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: Icon(
                allSelected ? Icons.deselect : Icons.select_all,
              ),
              tooltip: allSelected ? 'Desmarcar tudo' : 'Selecionar tudo',
              onPressed: () {
                if (allSelected) {
                  _clearSelection();
                } else {
                  _selectAll(filtered);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: 'Adicionar à playlist',
              onPressed: () => _addSelectedToPlaylist(filtered),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Excluir',
              onPressed: () => _confirmAndDelete(filtered),
            ),
          ],
        ),
      ),
    );
  }

  void _showSongOptions(BuildContext context, SongModel song) {
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
                _playSong(context, [song], 0);
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_box_outlined),
              title: const Text('Selecionar'),
              onTap: () {
                Navigator.pop(context);
                _enterSelectionWith(song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Adicionar à playlist'),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (_) => AddToPlaylistDialog(songs: [song]),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Detalhes da música'),
              onTap: () {
                Navigator.pop(context);
                _showSongDetails(context, song);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSongDetails(BuildContext context, SongModel song) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(song.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Artista: ${song.artist ?? "Desconhecido"}'),
            const SizedBox(height: 8),
            Text('Álbum: ${song.album ?? "Desconhecido"}'),
            const SizedBox(height: 8),
            Text(
                'Duração: ${formatDuration(Duration(milliseconds: song.duration ?? 0))}'),
            const SizedBox(height: 8),
            Text('Gênero: ${song.genre ?? "Desconhecido"}'),
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
}

/// Item isolado — só rebuilda por conta própria via Selector para
/// isCurrent/isPlaying. selected/selectionMode vêm de fora porque dependem
/// do estado de seleção da lista pai.
class _SongTile extends StatelessWidget {
  final SongModel song;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMoreTap;

  const _SongTile({
    required super.key,
    required this.song,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerController, ({bool isCurrent, bool isPlaying})>(
      selector: (_, controller) => (
        isCurrent: controller.isCurrentSong(song),
        isPlaying: controller.isCurrentlyPlaying(song),
      ),
      builder: (context, state, _) {
        return ListTile(
          selected: selected,
          selectedTileColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          leading: SizedBox(
            width: 48,
            height: 48,
            child: selectionMode
                ? Center(
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => onTap(),
                    ),
                  )
                : Opacity(
                    opacity: state.isCurrent ? 0.6 : 1.0,
                    child: ArtworkThumbnail(
                      id: song.id,
                      type: ArtworkType.AUDIO,
                      borderRadius: 6,
                    ),
                  ),
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: state.isCurrent
                  ? Theme.of(context).colorScheme.primary
                  : null,
              fontWeight: state.isCurrent ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            '${song.artist ?? "Artista desconhecido"} • ${song.album ?? "Álbum desconhecido"}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: selectionMode
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (state.isCurrent)
                      Icon(
                        state.isPlaying
                            ? Icons.volume_up
                            : Icons.pause_circle_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: onMoreTap,
                    ),
                  ],
                ),
          onTap: onTap,
          onLongPress: onLongPress,
        );
      },
    );
  }
}
