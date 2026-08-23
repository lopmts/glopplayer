import 'dart:async';

import 'package:flutter/material.dart';
import 'package:glopplayer/screens/pages/metadata_editor_screen.dart';
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

  // --- Filtros (artista / gênero) ---------------------------------------
  String? _artistFilter;
  String? _genreFilter;
  bool get _hasActiveFilter => _artistFilter != null || _genreFilter != null;

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

  /// Aplica o filtro de pastas (config da biblioteca) — usado como base
  /// tanto pra lista final quanto pra calcular as opções disponíveis nos
  /// dropdowns de artista/gênero.
  Iterable<SongModel> _folderScoped(List<String> folders) {
    Iterable<SongModel> base = widget.songs;
    if (folders.isNotEmpty) {
      base = base.where((song) => _isInsideAnyFolder(song.data, folders));
    }
    return base;
  }

  List<SongModel> _filteredSongs(List<String> folders) {
    Iterable<SongModel> base = _folderScoped(folders);

    if (_artistFilter != null) {
      base = base.where(
        (song) =>
            (song.artist?.trim().isNotEmpty == true
                ? song.artist!.trim()
                : 'Artista desconhecido') ==
            _artistFilter,
      );
    }

    if (_genreFilter != null) {
      base = base.where(
        (song) =>
            (song.genre?.trim().isNotEmpty == true
                ? song.genre!.trim()
                : 'Sem gênero') ==
            _genreFilter,
      );
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

  /// Artistas disponíveis dentro do escopo de pastas atual — não leva em
  /// conta o próprio filtro de artista (senão o dropdown "encolheria"
  /// pra uma única opção assim que algo fosse selecionado), mas respeita
  /// o filtro de gênero, pra a lista de artistas já vir "combinável".
  List<String> _availableArtists(List<String> folders) {
    Iterable<SongModel> base = _folderScoped(folders);
    if (_genreFilter != null) {
      base = base.where(
        (song) =>
            (song.genre?.trim().isNotEmpty == true
                ? song.genre!.trim()
                : 'Sem gênero') ==
            _genreFilter,
      );
    }
    final set = base
        .map((s) => s.artist?.trim().isNotEmpty == true
            ? s.artist!.trim()
            : 'Artista desconhecido')
        .toSet()
        .toList();
    set.sort();
    return set;
  }

  /// Gêneros/tipos disponíveis dentro do escopo de pastas atual, já
  /// considerando o filtro de artista ativo (mesma lógica do método
  /// acima, espelhada).
  List<String> _availableGenres(List<String> folders) {
    Iterable<SongModel> base = _folderScoped(folders);
    if (_artistFilter != null) {
      base = base.where(
        (song) =>
            (song.artist?.trim().isNotEmpty == true
                ? song.artist!.trim()
                : 'Artista desconhecido') ==
            _artistFilter,
      );
    }
    final set = base
        .map((s) =>
            s.genre?.trim().isNotEmpty == true ? s.genre!.trim() : 'Sem gênero')
        .toSet()
        .toList();
    set.sort();
    return set;
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

  void _applyFilters({String? artist, String? genre}) {
    setState(() {
      _artistFilter = artist;
      _genreFilter = genre;
      _visibleCount = _pageSize;
    });
  }

  void _clearFilters() {
    if (!_hasActiveFilter) return;
    setState(() {
      _artistFilter = null;
      _genreFilter = null;
      _visibleCount = _pageSize;
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

  // --- Edição de metadados -------------------------------------------------

  /// Abre a tela de edição de metadados pras músicas passadas. Funciona
  /// tanto pra uma única música (a partir do menu "..." de cada item)
  /// quanto pra várias de uma vez (a partir da barra de seleção).
  Future<void> _openMetadataEditor(List<SongModel> songs) async {
    if (songs.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MetadataEditorScreen(
          songs: songs,
          onSaved: (savedSongs) async {
            // Reescaneia a biblioteca pra atualizar título/artista/capa
            // exibidos nas listas e no cache local.
            await context.read<LibraryController>().scanLibrary();
          },
        ),
      ),
    );

    if (mounted && _selectionMode) {
      _clearSelection();
    }
  }

  // --- Filtro por artista/gênero -----------------------------------------

  Future<void> _showFilterSheet(List<String> folders) async {
    final artists = _availableArtists(folders);
    final genres = _availableGenres(folders);

    String? tempArtist = _artistFilter;
    String? tempGenre = _genreFilter;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Filtrar músicas',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: (tempArtist == null && tempGenre == null)
                            ? null
                            : () => setSheetState(() {
                                  tempArtist = null;
                                  tempGenre = null;
                                }),
                        child: const Text('Limpar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (artists.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: tempArtist,
                      decoration: InputDecoration(
                        labelText: 'Artista',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      hint: const Text('Todos'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Todos'),
                        ),
                        ...artists.map(
                          (a) => DropdownMenuItem<String>(
                            value: a,
                            child: Text(a, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (v) => setSheetState(() => tempArtist = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (genres.isNotEmpty)
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: tempGenre,
                      decoration: InputDecoration(
                        labelText: 'Gênero / tipo',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      hint: const Text('Todos'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Todos'),
                        ),
                        ...genres.map(
                          (g) => DropdownMenuItem<String>(
                            value: g,
                            child: Text(g, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (v) => setSheetState(() => tempGenre = v),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () {
                      _applyFilters(artist: tempArtist, genre: tempGenre);
                      Navigator.pop(sheetContext);
                    },
                    child: const Text('Aplicar filtros'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final folders = context.watch<LibraryController>().folders;
    final filtered = _filteredSongs(folders);
    final visible = filtered.take(_visibleCount).toList();

    return Column(
      children: [
        _selectionMode
            ? _buildSelectionBar(filtered)
            : _buildSearchBar(folders),
        if (!_selectionMode && _hasActiveFilter) _buildActiveFilterChips(),
        Expanded(
          child: widget.songs.isEmpty
              ? const Center(
                  child: Text('Nenhuma música encontrada no aparelho'))
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        _query.isEmpty && !_hasActiveFilter
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
          ),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: _hasActiveFilter,
            smallSize: 8,
            child: IconButton.filledTonal(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filtrar por artista/gênero',
              onPressed: () => _showFilterSheet(folders),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (_artistFilter != null)
            InputChip(
              label: Text(_artistFilter!),
              avatar: const Icon(Icons.person_outline, size: 18),
              onDeleted: () => _applyFilters(artist: null, genre: _genreFilter),
            ),
          if (_genreFilter != null)
            InputChip(
              label: Text(_genreFilter!),
              avatar: const Icon(Icons.category_outlined, size: 18),
              onDeleted: () =>
                  _applyFilters(artist: _artistFilter, genre: null),
            ),
          ActionChip(
            label: const Text('Limpar tudo'),
            avatar: const Icon(Icons.filter_alt_off, size: 18),
            onPressed: _clearFilters,
          ),
        ],
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
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar metadados',
              onPressed: () => _openMetadataEditor(_selectedSongs(filtered)),
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
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar metadados'),
              onTap: () {
                Navigator.pop(context);
                _openMetadataEditor([song]);
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
