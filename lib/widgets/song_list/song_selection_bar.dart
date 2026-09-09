import 'package:flutter/material.dart';

class SongSelectionBar extends StatelessWidget {
  final int selectedCount;
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback onToggleSelectAll;
  final VoidCallback onEditMetadata;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onDelete;

  const SongSelectionBar({
    super.key,
    required this.selectedCount,
    required this.allSelected,
    required this.onClose,
    required this.onToggleSelectAll,
    required this.onEditMetadata,
    required this.onAddToPlaylist,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancelar seleção',
              onPressed: onClose,
            ),
            Expanded(
              child: Text(
                '$selectedCount selecionada${selectedCount == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
              tooltip: allSelected ? 'Desmarcar tudo' : 'Selecionar tudo',
              onPressed: onToggleSelectAll,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar metadados',
              onPressed: onEditMetadata,
            ),
            IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: 'Adicionar à playlist',
              onPressed: onAddToPlaylist,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Excluir',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
