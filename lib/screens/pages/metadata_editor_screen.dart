import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:glopplayer/services/artwork_cache_service.dart';
import 'package:glopplayer/services/cover_search_service.dart';
import 'package:glopplayer/services/media_scanner_service.dart';
import 'package:glopplayer/services/metadata_service.dart';
import 'package:glopplayer/widgets/dynamic_cover_background.dart';
import 'package:image_picker/image_picker.dart';
import 'package:metadata_god/metadata_god.dart' show Metadata, Picture;
import 'package:on_audio_query/on_audio_query.dart';

enum _PendingCoverAction { none, setBytes, remove }

/// Tela de edição de metadados. Funciona tanto pra uma música (todos os
/// campos + título/nº da faixa) quanto pra várias de uma vez (edição em
/// lote — campos que diferem entre as músicas aparecem como "Vários
/// valores" e só são alterados se o usuário digitar algo).
///
/// Uso:
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => MetadataEditorScreen(
///     songs: selectedSongs,
///     onSaved: (songs) async {
///       await context.read<LibraryController>().scanLibrary();
///     },
///   ),
/// ));
/// ```
class MetadataEditorScreen extends StatefulWidget {
  final List<SongModel> songs;

  /// Chamado depois de salvar com sucesso — use pra invalidar seu cache de
  /// artwork e/ou disparar um rescan da biblioteca.
  final Future<void> Function(List<SongModel> songs)? onSaved;

  const MetadataEditorScreen({
    super.key,
    required this.songs,
    this.onSaved,
  });

  @override
  State<MetadataEditorScreen> createState() => _MetadataEditorScreenState();
}

class _MetadataEditorScreenState extends State<MetadataEditorScreen> {
  bool get _isBatch => widget.songs.length > 1;

  bool _loading = true;
  bool _saving = false;
  int _saveProgress = 0;

  late final TextEditingController _titleCtrl;
  late final TextEditingController _artistCtrl;
  late final TextEditingController _albumCtrl;
  late final TextEditingController _albumArtistCtrl;
  late final TextEditingController _genreCtrl;
  late final TextEditingController _yearCtrl;
  late final TextEditingController _trackNumberCtrl;
  late final TextEditingController _discNumberCtrl;

  final Set<String> _dirtyFields = {};

  Uint8List? _previewCoverBytes;
  _PendingCoverAction _pendingCover = _PendingCoverAction.none;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _artistCtrl = TextEditingController();
    _albumCtrl = TextEditingController();
    _albumArtistCtrl = TextEditingController();
    _genreCtrl = TextEditingController();
    _yearCtrl = TextEditingController();
    _trackNumberCtrl = TextEditingController();
    _discNumberCtrl = TextEditingController();
    _loadInitialValues();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    _albumArtistCtrl.dispose();
    _genreCtrl.dispose();
    _yearCtrl.dispose();
    _trackNumberCtrl.dispose();
    _discNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialValues() async {
    final tags = <Metadata?>[];
    for (final song in widget.songs) {
      Metadata? meta;
      try {
        meta = await MetadataService.read(song.data)
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        meta = null;
      }
      tags.add(meta);
    }

    // Se todas as músicas tiverem o mesmo valor pro campo, pré-preenche;
    // senão deixa em branco (mostrando "Vários valores" como hint).
    String common(Iterable<String?> values) {
      final set = values.map((v) => (v ?? '').trim()).toSet();
      return set.length == 1 ? set.first : '';
    }

    String commonInt(Iterable<int?> values) {
      final set = values.map((v) => v?.toString() ?? '').toSet();
      return set.length == 1 ? set.first : '';
    }

    _titleCtrl.text =
        _isBatch ? '' : (tags.first?.title ?? widget.songs.first.title);
    _artistCtrl.text = common([
      for (var i = 0; i < tags.length; i++)
        tags[i]?.artist ?? widget.songs[i].artist,
    ]);
    _albumCtrl.text = common([
      for (var i = 0; i < tags.length; i++)
        tags[i]?.album ?? widget.songs[i].album,
    ]);
    _albumArtistCtrl.text = common(tags.map((t) => t?.albumArtist));
    _genreCtrl.text = common([
      for (var i = 0; i < tags.length; i++)
        tags[i]?.genre ?? widget.songs[i].genre,
    ]);
    _yearCtrl.text = commonInt(tags.map((t) => t?.year));
    _trackNumberCtrl.text =
        _isBatch ? '' : (tags.first?.trackNumber?.toString() ?? '');
    _discNumberCtrl.text = commonInt(tags.map((t) => t?.discNumber));
    var cover = tags.first?.picture?.data;

    // 1. Tenta capa embutida primeiro (mais rápida e confiável)
    if (tags.first?.picture?.data != null) {
      cover = tags.first!.picture!.data;
    }
    // 2. Se não tiver capa embutida, busca do cache local
    else {
      final path = await ArtworkCacheService.instance.getArtworkPath(
        widget.songs.first.id,
        ArtworkType.AUDIO,
      );
      if (path != null) {
        try {
          cover = await File(path).readAsBytes();
        } catch (_) {
          // arquivo de cache sumiu/corrompeu — segue sem capa
        }
      }
    }

    // 3. Se ainda não tiver capa, tenta extrair do sistema
    if (cover == null && !_isBatch) {
      // O OnAudioQuery já foi chamado pelo ArtworkCacheService
      // mas podemos tentar novamente como fallback
      try {
        final systemArtwork = await OnAudioQuery().queryArtwork(
          widget.songs.first.id,
          ArtworkType.AUDIO,
          format: ArtworkFormat.JPEG,
          size: 400,
          quality: 85,
        );
        if (systemArtwork != null && systemArtwork.isNotEmpty) {
          cover = systemArtwork;
          // Salva no cache para uso futuro
          await ArtworkCacheService.instance.saveArtwork(
            widget.songs.first.id,
            ArtworkType.AUDIO,
            cover!,
          );
        }
      } catch (_) {
        // ignora erros
      }
    }

    _previewCoverBytes = cover;

    if (mounted) setState(() => _loading = false);

    if (!_isBatch) {
      _previewCoverBytes = tags.first?.picture?.data;
    }

    if (mounted) setState(() => _loading = false);
  }

  void _markDirty(String field) => _dirtyFields.add(field);

  // --- Capa ----------------------------------------------------------------

  Future<void> _extractEmbeddedCover() async {
    if (_isBatch) return; // extração é por arquivo — não se aplica em lote
    final bytes =
        await MetadataService.extractEmbeddedCover(widget.songs.first.data);
    if (bytes == null) {
      _showSnack('Esta música não tem capa embutida.');
      return;
    }
    setState(() {
      _previewCoverBytes = bytes;
      // Já é a capa atual do arquivo — não precisa marcar como pendente.
      _pendingCover = _PendingCoverAction.none;
    });
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    setState(() {
      _previewCoverBytes = bytes;
      _pendingCover = _PendingCoverAction.setBytes;
    });
  }

  Future<void> _searchOnline() async {
    // Primeiro, mostra um diálogo de carregamento enquanto busca localmente
    if (_previewCoverBytes == null && !_isBatch) {
      // Mostra um snackbar indicando que está buscando localmente
      final snackBar = SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            const Text('Verificando capa local...'),
          ],
        ),
        duration: const Duration(seconds: 2),
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);

      // Tenta carregar do cache local novamente
      final path = await ArtworkCacheService.instance.getArtworkPath(
        widget.songs.first.id,
        ArtworkType.AUDIO,
      );
      if (path != null) {
        try {
          final bytes = await File(path).readAsBytes();
          if (bytes.isNotEmpty) {
            setState(() {
              _previewCoverBytes = bytes;
              _pendingCover = _PendingCoverAction.none;
            });
            _showSnack('Capa local encontrada!');
            return;
          }
        } catch (_) {}
      }
    }

    // Se não encontrou localmente, mostra a busca online
    final query = [_artistCtrl.text, _albumCtrl.text]
        .where((s) => s.trim().isNotEmpty)
        .join(' ');

    final result = await showModalBottomSheet<CoverSearchResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CoverSearchSheet(initialQuery: query),
    );

    if (result == null) return;

    try {
      final bytes =
          await CoverSearchService.downloadBytes(result.artworkUrlHigh);
      setState(() {
        _previewCoverBytes = bytes;
        _pendingCover = _PendingCoverAction.setBytes;
      });
    } catch (e) {
      _showSnack('Não foi possível baixar essa capa.');
    }
  }

  void _removeCover() {
    setState(() {
      _previewCoverBytes = null;
      _pendingCover = _PendingCoverAction.remove;
    });
  }

  // --- Salvar

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveProgress = 0;
    });

    var successCount = 0;
    for (final song in widget.songs) {
      final ok = await MetadataService.writeFields(
        song.data,
        title: (!_isBatch && _dirtyFields.contains('title'))
            ? _titleCtrl.text.trim()
            : null,
        artist:
            _dirtyFields.contains('artist') ? _artistCtrl.text.trim() : null,
        album: _dirtyFields.contains('album') ? _albumCtrl.text.trim() : null,
        albumArtist: _dirtyFields.contains('albumArtist')
            ? _albumArtistCtrl.text.trim()
            : null,
        genre: _dirtyFields.contains('genre') ? _genreCtrl.text.trim() : null,
        year: _dirtyFields.contains('year')
            ? int.tryParse(_yearCtrl.text.trim())
            : null,
        trackNumber: (!_isBatch && _dirtyFields.contains('trackNumber'))
            ? int.tryParse(_trackNumberCtrl.text.trim())
            : null,
        discNumber: _dirtyFields.contains('discNumber')
            ? int.tryParse(_discNumberCtrl.text.trim())
            : null,
        overridePicture: _pendingCover == _PendingCoverAction.setBytes &&
                _previewCoverBytes != null
            ? Picture(data: _previewCoverBytes!, mimeType: 'image/jpeg')
            : null,
        removePicture: _pendingCover == _PendingCoverAction.remove,
      );

      if (ok) {
        successCount++;
        // Avisa o MediaStore do Android que o arquivo mudou. Sem isso, o
        // on_audio_query (e o app de galeria) continuam mostrando tags e
        // capa antigas em cache até o próximo scan automático do sistema.
        await MediaScannerService.scanFile(song.data);
      }

      if (mounted) setState(() => _saveProgress++);
    }

    if (widget.onSaved != null) {
      await widget.onSaved!(widget.songs);
    }

    if (!mounted) return;
    setState(() => _saving = false);

    Navigator.of(context).pop(successCount);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          successCount == widget.songs.length
              ? (_isBatch
                  ? '$successCount músicas atualizadas'
                  : 'Metadados atualizados')
              : '$successCount de ${widget.songs.length} músicas atualizadas — algumas falharam',
        ),
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isBatch
            ? 'Editar ${widget.songs.length} músicas'
            : 'Editar metadados'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: widget.songs.length > 1
                          ? _saveProgress / widget.songs.length
                          : null,
                    ),
                  )
                : const Text('Salvar'),
          ),
        ],
      ),
      body: DynamicCoverBackground(
        coverBytes: _previewCoverBytes,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildCoverSection(),
            const SizedBox(height: 24),
            if (_isBatch) _buildBatchNotice(),
            if (!_isBatch)
              _buildField(
                controller: _titleCtrl,
                label: 'Título',
                fieldKey: 'title',
              ),
            _buildField(
                controller: _artistCtrl, label: 'Artista', fieldKey: 'artist'),
            _buildField(
                controller: _albumCtrl, label: 'Álbum', fieldKey: 'album'),
            _buildField(
              controller: _albumArtistCtrl,
              label: 'Artista do álbum',
              fieldKey: 'albumArtist',
            ),
            _buildField(
                controller: _genreCtrl, label: 'Gênero', fieldKey: 'genre'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildField(
                    controller: _yearCtrl,
                    label: 'Ano',
                    fieldKey: 'year',
                    keyboardType: TextInputType.number,
                  ),
                ),
                if (!_isBatch) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _trackNumberCtrl,
                      label: 'Faixa nº',
                      fieldKey: 'trackNumber',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                Expanded(
                  child: _buildField(
                    controller: _discNumberCtrl,
                    label: 'Disco nº',
                    fieldKey: 'discNumber',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchNotice() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        'Editando ${widget.songs.length} músicas de uma vez. Campos com '
        '"Vários valores" estão diferentes entre as músicas selecionadas — '
        'só o que você preencher aqui será aplicado a todas.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String fieldKey,
    TextInputType? keyboardType,
  }) {
    final isMixed = _isBatch && controller.text.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: (_) => _markDirty(fieldKey),
        decoration: InputDecoration(
          labelText: label,
          hintText: isMixed ? 'Vários valores' : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildCoverSection() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _previewCoverBytes != null
              ? Image.memory(_previewCoverBytes!,
                  width: 180, height: 180, fit: BoxFit.cover)
              : Container(
                  width: 180,
                  height: 180,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(
                    _isBatch ? Icons.library_music : Icons.music_note,
                    size: 56,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!_isBatch)
              OutlinedButton.icon(
                onPressed: _extractEmbeddedCover,
                icon: const Icon(Icons.image_search, size: 18),
                label: const Text('Extrair capa'),
              ),
            OutlinedButton.icon(
              onPressed: _pickFromGallery,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Galeria'),
            ),
            OutlinedButton.icon(
              onPressed: _searchOnline,
              icon: const Icon(Icons.travel_explore, size: 18),
              label: const Text('Buscar online'),
            ),
            OutlinedButton.icon(
              onPressed: _removeCover,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Remover'),
            ),
          ],
        ),
        if (_isBatch)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _pendingCover == _PendingCoverAction.none
                  ? 'Nenhuma alteração de capa — cada música mantém a sua.'
                  : 'Essa capa será aplicada às ${widget.songs.length} músicas selecionadas.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

/// Bottom sheet de busca de capas online (iTunes Search API).
class _CoverSearchSheet extends StatefulWidget {
  final String initialQuery;
  const _CoverSearchSheet({required this.initialQuery});

  @override
  State<_CoverSearchSheet> createState() => _CoverSearchSheetState();
}

class _CoverSearchSheetState extends State<_CoverSearchSheet> {
  late final TextEditingController _queryCtrl;
  List<CoverSearchResult> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _queryCtrl = TextEditingController(text: widget.initialQuery);
    if (widget.initialQuery.trim().isNotEmpty) _search();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final results = await CoverSearchService.search(query: _queryCtrl.text);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Erro ao buscar capas. Verifique sua conexão.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryCtrl,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        labelText: 'Buscar álbum ou artista',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _loading ? null : _search,
                    icon: const Icon(Icons.search),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _results.isEmpty
                        ? const Center(child: Text('Nenhum resultado ainda.'))
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.8,
                            ),
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final r = _results[index];
                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.pop(context, r),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          r.artworkUrlSmall,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                                  Icons.broken_image_outlined),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      r.collectionName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
