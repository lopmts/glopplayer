import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../../controllers/favorites_controller.dart';
import '../../widgets/artwork_thumbnail.dart';

/// Tela de músicas favoritadas. Permite filtrar por tipo/gênero e por
/// artista, remover uma favorita individualmente, e desmarcar todas de
/// uma vez.
class FavoritesScreen extends StatefulWidget {
  final void Function(SongModel song) onSongTap;

  const FavoritesScreen({super.key, required this.onSongTap});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  String? _genreFilter;
  String? _artistFilter;

  Future<void> _confirmClearAll(FavoritesController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desmarcar todas'),
        content: const Text(
          'Isso remove todas as músicas da lista de favoritas. '
          'Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desmarcar todas'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await controller.clearAll();
      if (!mounted) return;
      setState(() {
        _genreFilter = null;
        _artistFilter = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Favoritas removidas')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FavoritesController>(
      builder: (context, controller, _) {
        if (controller.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Se o filtro selecionado deixou de existir (ex: última música
        // daquele artista foi removida), reseta pra não travar numa
        // lista vazia sem explicação.
        final genres = controller.availableGenres;
        final artists = controller.availableArtists;
        if (_genreFilter != null && !genres.contains(_genreFilter)) {
          _genreFilter = null;
        }
        if (_artistFilter != null && !artists.contains(_artistFilter)) {
          _artistFilter = null;
        }

        var entries = controller.entries;
        if (_genreFilter != null) {
          entries = entries.where((e) => e.genre == _genreFilter).toList();
        }
        if (_artistFilter != null) {
          entries = entries.where((e) => e.artist == _artistFilter).toList();
        }

        final hasAnyFavorite = controller.entries.isNotEmpty;
        final hasActiveFilter = _genreFilter != null || _artistFilter != null;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Favoritas'),
            actions: [
              if (hasAnyFavorite)
                IconButton(
                  icon: const Icon(Icons.playlist_remove),
                  tooltip: 'Desmarcar todas',
                  onPressed: () => _confirmClearAll(controller),
                ),
            ],
          ),
          body: Column(
            children: [
              if (genres.isNotEmpty || artists.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Row(
                    children: [
                      if (genres.isNotEmpty)
                        Expanded(
                          child: _FilterDropdown(
                            label: 'Tipo / gênero',
                            value: _genreFilter,
                            items: genres,
                            onChanged: (v) => setState(() => _genreFilter = v),
                          ),
                        ),
                      if (genres.isNotEmpty && artists.isNotEmpty)
                        const SizedBox(width: 12),
                      if (artists.isNotEmpty)
                        Expanded(
                          child: _FilterDropdown(
                            label: 'Artista',
                            value: _artistFilter,
                            items: artists,
                            onChanged: (v) => setState(() => _artistFilter = v),
                          ),
                        ),
                    ],
                  ),
                ),
              if (hasActiveFilter)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        _genreFilter = null;
                        _artistFilter = null;
                      }),
                      icon: const Icon(Icons.filter_alt_off, size: 18),
                      label: const Text('Limpar filtros'),
                    ),
                  ),
                ),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            hasAnyFavorite
                                ? 'Nenhuma música corresponde aos filtros.'
                                : 'Nenhuma música favoritada ainda.\n'
                                    'Toque no coração na tela do player '
                                    'pra favoritar.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, i) {
                          final e = entries[i];
                          return ListTile(
                            leading: SizedBox(
                              width: 48,
                              height: 48,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: ArtworkThumbnail(
                                  id: e.songId,
                                  type: ArtworkType.AUDIO,
                                  borderRadius: 6,
                                ),
                              ),
                            ),
                            title: Text(
                              e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              (e.genre != null && e.genre!.isNotEmpty)
                                  ? '${e.artist} • ${e.genre}'
                                  : e.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.favorite,
                                  color: Colors.redAccent),
                              tooltip: 'Remover dos favoritos',
                              onPressed: () => controller.remove(e.songId),
                            ),
                            onTap: () => widget.onSongTap(e.toSongModel()),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      hint: const Text('Todos'),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('Todos')),
        ...items.map(
          (v) => DropdownMenuItem<String>(
            value: v,
            child: Text(v, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}
