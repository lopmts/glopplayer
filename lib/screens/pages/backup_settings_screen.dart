import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:glopplayer/controllers/favorites_controller.dart';
import 'package:glopplayer/provider/playlist_provider.dart';
import 'package:glopplayer/services/backup_progress_notification_service.dart';
import 'package:glopplayer/services/backup_restore_service.dart';
import 'package:provider/provider.dart';

class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  final _notifications = BackupProgressNotificationService.instance;
  late Future<BackupDataSummary> _summaryFuture;
  bool _handlingBackup = false;
  double? _progress;
  String? _progressLabel;
  int _lastNotifiedProgress = 0;
  String _activeTitle = '';

  @override
  void initState() {
    super.initState();
    _summaryFuture = BackupRestoreService.getDataSummary();
  }

  Future<void> _reportProgress(int current, int total) async {
    if (mounted) {
      setState(() {
        _progress = total == 0 ? 1 : current / total;
        _progressLabel =
            total == 0 ? 'Preparando...' : '$current de $total itens';
      });
    }

    final updateInterval = (total / 20).ceil().clamp(1, total);
    if (current != total && current - _lastNotifiedProgress < updateInterval) {
      return;
    }
    _lastNotifiedProgress = current;
    await _notifications.updateProgress(
      title: _activeTitle,
      current: current,
      total: total,
    );
  }

  void _startProgress(String title) {
    _activeTitle = title;
    _lastNotifiedProgress = 0;
    _progress = null;
    _progressLabel = null;
  }

  Future<void> _exportBackup() async {
    if (_handlingBackup) return;
    setState(() {
      _handlingBackup = true;
      _startProgress('Exportando backup');
    });

    var notificationStarted = false;
    try {
      await _notifications.showIndeterminate(
        title: 'Exportando backup',
        body: 'Preparando playlists e favoritos...',
      );
      notificationStarted = true;

      final json = await BackupRestoreService.exportJson(
        onProgress: _reportProgress,
      );
      final date = DateTime.now().toIso8601String().split('T').first;
      final path = await FilePicker.saveFile(
        dialogTitle: 'Salvar backup do GlopPlay',
        fileName: 'glopplayer-backup-$date.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        mimeType: 'application/json',
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (path == null) {
        await _notifications.dismiss();
        notificationStarted = false;
        return;
      }

      await _notifications.showCompleted(
        title: 'Backup exportado',
        body: 'O arquivo de backup foi salvo com sucesso.',
      );
      notificationStarted = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup exportado com sucesso.')),
      );
    } catch (error) {
      if (notificationStarted) await _notifications.showFailed('Exportação');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível exportar o backup: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _handlingBackup = false;
          _progress = null;
          _progressLabel = null;
        });
      }
    }
  }

  Future<void> _importBackup() async {
    if (_handlingBackup) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar backup?'),
        content: const Text(
          'As playlists, músicas das playlists e favoritos do arquivo serão '
          'mesclados com os dados atuais. Nada será apagado. Itens já '
          'existentes não serão duplicados. Os arquivos de música não fazem '
          'parte do backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Escolher arquivo'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _handlingBackup = true;
      _startProgress('Importando backup');
    });

    var notificationStarted = false;
    try {
      final selection = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (selection == null || !mounted) return;

      await _notifications.showIndeterminate(
        title: 'Importando backup',
        body: 'Lendo o arquivo selecionado...',
      );
      notificationStarted = true;
      final bytes = await selection.readAsBytes();
      final backup = AppBackup.decode(utf8.decode(bytes));
      final result = await BackupRestoreService.importBackup(
        backup,
        onProgress: _reportProgress,
      );
      if (!mounted) return;

      final playlistProvider = context.read<PlaylistProvider>();
      final favoritesController = context.read<FavoritesController>();
      await playlistProvider.loadPlaylists();
      await favoritesController.refresh();
      _summaryFuture = BackupRestoreService.getDataSummary();
      await _notifications.showCompleted(
        title: 'Backup restaurado',
        body: 'Os dados foram mesclados com sucesso.',
      );
      notificationStarted = false;
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Backup restaurado: ${result.playlists} playlists processadas, '
            '${result.playlistSongs} músicas e ${result.favorites} favoritos '
            'adicionados.',
          ),
        ),
      );
    } catch (error) {
      if (notificationStarted) await _notifications.showFailed('Importação');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível restaurar o backup: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _handlingBackup = false;
          _progress = null;
          _progressLabel = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Backup e restauração')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Dados disponíveis para exportação',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: FutureBuilder<BackupDataSummary>(
              future: _summaryFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: const Text('Não foi possível carregar os dados'),
                    subtitle: Text('${snapshot.error}'),
                    trailing: IconButton(
                      tooltip: 'Tentar novamente',
                      onPressed: () => setState(
                        () => _summaryFuture =
                            BackupRestoreService.getDataSummary(),
                      ),
                      icon: const Icon(Icons.refresh),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const ListTile(
                    leading: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    title: Text('Carregando contagem...'),
                  );
                }
                final summary = snapshot.data!;
                return Column(
                  children: [
                    _CountTile(
                      icon: Icons.queue_music_outlined,
                      title: 'Playlists',
                      count: summary.playlists,
                    ),
                    const Divider(height: 1, indent: 56),
                    _CountTile(
                      icon: Icons.music_note_outlined,
                      title: 'Músicas nas playlists',
                      count: summary.playlistSongs,
                    ),
                    const Divider(height: 1, indent: 56),
                    _CountTile(
                      icon: Icons.favorite_border,
                      title: 'Favoritos',
                      count: summary.favorites,
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'O backup salva playlists, músicas associadas e favoritos. '
            'Os arquivos de áudio não são copiados.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('Exportar dados'),
                  subtitle: const Text('Salvar os dados em um arquivo JSON'),
                  trailing: _handlingBackup
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _handlingBackup ? null : _exportBackup,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Importar dados'),
                  subtitle: const Text('Restaurar dados de um backup JSON'),
                  trailing: _handlingBackup
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _handlingBackup ? null : _importBackup,
                ),
              ],
            ),
          ),
          if (_handlingBackup) ...[
            const SizedBox(height: 20),
            LinearProgressIndicator(value: _progress),
            if (_progressLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                _progressLabel!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;

  const _CountTile({
    required this.icon,
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Text('$count', style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
