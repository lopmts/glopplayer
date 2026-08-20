import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:glopplayer/controllers/library_controller.dart';
import 'package:provider/provider.dart';

class LocalLibraryScreen extends StatelessWidget {
  const LocalLibraryScreen({super.key});

  String _formatLastScanned(DateTime? date) {
    if (date == null) return 'Nunca';
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 10) return 'Agora mesmo';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s atrás';
    if (diff.inHours < 1) return '${diff.inMinutes}min atrás';
    if (diff.inDays < 1) return '${diff.inHours}h atrás';
    return '${diff.inDays}d atrás';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LibraryController>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!controller.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Local Library')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _StatsCard(controller: controller, formatDate: _formatLastScanned),
          const SizedBox(height: 24),
          _SectionLabel('Scan Settings'),
          _Card(
            children: [
              _SwitchTile(
                icon: Icons.library_music_outlined,
                title: 'Enable Local Library',
                subtitle: 'Scan and track your existing music',
                value: controller.enabled,
                onChanged: controller.setEnabled,
              ),
              const _TileDivider(),
              _FolderListSection(controller: controller),
              const _TileDivider(),
              _SwitchTile(
                icon: Icons.content_copy_outlined,
                title: 'Show Duplicate Indicator',
                subtitle: 'Show when searching for existing tracks',
                value: controller.showDuplicateIndicator,
                onChanged: controller.setShowDuplicateIndicator,
              ),
              const _TileDivider(),
              _NavTile(
                icon: Icons.sync_outlined,
                title: 'Auto Scan',
                subtitle: controller.autoScanFrequency.label,
                onTap: () => _openAutoScanMenu(context, controller),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionLabel('Actions'),
          _Card(
            children: [
              _ActionTile(
                icon: Icons.refresh,
                title: 'Scan Library',
                subtitle: 'Scan for audio files',
                enabled: controller.enabled && !controller.isScanning,
                onTap: controller.scanLibrary,
              ),
              const _TileDivider(),
              _ActionTile(
                icon: Icons.sync,
                title: 'Force Full Scan',
                subtitle: 'Rescan all files, ignoring cache',
                enabled: controller.enabled && !controller.isScanning,
                onTap: controller.forceFullScan,
              ),
              const _TileDivider(),
              _ActionTile(
                icon: Icons.cleaning_services_outlined,
                title: 'Cleanup Missing Files',
                subtitle: 'Remove entries for files that no longer exist',
                enabled: controller.enabled &&
                    !controller.isScanning &&
                    controller.trackCount > 0,
                onTap: () async {
                  final removed = await controller.cleanupMissingFiles();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text('$removed arquivo(s) removidos do cache')),
                    );
                  }
                },
              ),
              const _TileDivider(),
              _ActionTile(
                icon: Icons.delete_outline,
                title: 'Clear Library',
                subtitle: 'Erase local cache and stats',
                enabled: controller.enabled &&
                    !controller.isScanning &&
                    controller.trackCount > 0,
                destructive: true,
                onTap: () => _confirmClearLibrary(context, controller),
              ),
            ],
          ),
          if (controller.isScanning) ...[
            const SizedBox(height: 24),
            _ScanProgressCard(controller: controller),
          ],
        ],
      ),
    );
  }

  Future<void> _openAutoScanMenu(
      BuildContext context, LibraryController controller) async {
    final cs = Theme.of(context).colorScheme;
    final selected = await showModalBottomSheet<AutoScanFrequency>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final freq in AutoScanFrequency.values)
              ListTile(
                title: Text(freq.label),
                trailing: controller.autoScanFrequency == freq
                    ? Icon(Icons.check, color: cs.primary)
                    : null,
                onTap: () => Navigator.pop(context, freq),
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await controller.setAutoScanFrequency(selected);
    }
  }

  Future<void> _confirmClearLibrary(
      BuildContext context, LibraryController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar biblioteca?'),
        content: const Text(
          'Isso apaga o cache local (contagem de faixas e histórico de scan). '
          'Seus arquivos de música não são afetados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.clearLibrary();
    }
  }
}

/// Bloco de "Library Folders" — mostra até 3 pastas com opção de remover
/// cada uma, e um botão pra adicionar (abre o seletor nativo de pasta).
class _FolderListSection extends StatelessWidget {
  final LibraryController controller;
  const _FolderListSection({required this.controller});

  Future<void> _pickFolder(BuildContext context) async {
    if (!controller.canAddMoreFolders) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Máximo de ${controller.maxFolders} pastas atingido'),
        ),
      );
      return;
    }

    final path = await FilePicker.getDirectoryPath();
    if (path == null) return; // usuário cancelou o seletor

    final result = await controller.addFolder(path);
    if (!context.mounted) return;

    switch (result) {
      case AddFolderResult.success:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Pasta adicionada e biblioteca atualizada')),
        );
        break;
      case AddFolderResult.alreadyExists:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Essa pasta já está na lista')),
        );
        break;
      case AddFolderResult.limitReached:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Máximo de ${controller.maxFolders} pastas atingido'),
          ),
        );
        break;
    }
  }

  Future<void> _confirmRemove(BuildContext context, String path) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover pasta?'),
        content: Text(
          'As músicas de "$path" deixarão de aparecer na biblioteca.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.removeFolder(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, color: cs.onSurface, size: 24),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Library Folders',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      controller.folders.isEmpty
                          ? 'Biblioteca inteira (nenhuma pasta específica)'
                          : '${controller.folders.length}/${controller.maxFolders} pastas selecionadas',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.add_circle_outline, color: cs.primary),
                tooltip: 'Adicionar pasta',
                onPressed: controller.canAddMoreFolders
                    ? () => _pickFolder(context)
                    : null,
              ),
            ],
          ),
          if (controller.folders.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final folder in controller.folders)
              Padding(
                padding: const EdgeInsets.only(left: 44, top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        folder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close,
                          size: 18, color: cs.onSurfaceVariant),
                      onPressed: () => _confirmRemove(context, folder),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final LibraryController controller;
  final String Function(DateTime?) formatDate;

  const _StatsCard({required this.controller, required this.formatDate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.music_note, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 20),
          Text(
            '${controller.trackCount}',
            style: theme.textTheme.displaySmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'tracks',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.history, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Last scanned: ${formatDate(controller.lastScannedAt)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScanProgressCard extends StatelessWidget {
  final LibraryController controller;
  const _ScanProgressCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final hasTotal = controller.scanTotal > 0;
    final progress =
        hasTotal ? controller.scanCurrent / controller.scanTotal : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Escaneando biblioteca...',
            style: theme.textTheme.titleSmall?.copyWith(color: cs.onSurface),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(cs.primary),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasTotal
                ? '${controller.scanCurrent} de ${controller.scanTotal}'
                : 'Procurando arquivos...',
            style:
                theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: children),
    );
  }
}

class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
        height: 1, indent: 68, color: cs.outlineVariant.withOpacity(0.3));
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: cs.onSurface, size: 24),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: cs.onSurface, fontWeight: FontWeight.w500),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: cs.onSurface, size: 24),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: cs.onSurface, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final bool destructive;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = !enabled
        ? cs.onSurfaceVariant.withOpacity(0.4)
        : destructive
            ? cs.error
            : cs.onSurface;

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: !enabled
                          ? cs.onSurfaceVariant.withOpacity(0.4)
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (enabled) Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
