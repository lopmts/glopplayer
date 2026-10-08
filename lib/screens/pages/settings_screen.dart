import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:glopplayer/controllers/favorites_controller.dart';
import 'package:glopplayer/provider/playlist_provider.dart';
import 'package:glopplayer/services/backup_restore_service.dart';
import 'package:glopplayer/services/update_service.dart';
import 'package:glopplayer/widgets/update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = '';
  bool _checkingUpdate = false;
  bool _handlingBackup = false;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _appVersion = '${info.version} (${info.buildNumber})';
    });
  }

  /// Checagem manual disparada pelo tile "Verificar atualizações".
  /// Diferente da checagem silenciosa do boot: aqui sempre damos um
  /// feedback visual, seja update disponível, já atualizado ou erro.
  Future<void> _checkForUpdatesManually() async {
    if (_checkingUpdate) return;

    setState(() => _checkingUpdate = true);

    final result = await UpdateService.instance.checkForUpdate();

    if (!mounted) return;
    setState(() => _checkingUpdate = false);

    switch (result.status) {
      case UpdateCheckStatus.updateAvailable:
        showUpdateDialog(
          context,
          result.release!,
          currentVersion: result.currentVersion,
        );
        break;

      case UpdateCheckStatus.upToDate:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Você já está na versão mais recente. 🎉'),
          ),
        );
        break;

      case UpdateCheckStatus.error:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.error ?? 'Não foi possível checar atualizações.',
            ),
            action: SnackBarAction(
              label: 'Tentar de novo',
              onPressed: _checkForUpdatesManually,
            ),
          ),
        );
        break;
    }
  }

  Future<void> _exportBackup() async {
    if (_handlingBackup) return;
    setState(() => _handlingBackup = true);

    try {
      final json = await BackupRestoreService.exportJson();
      final date = DateTime.now().toIso8601String().split('T').first;
      final path = await FilePicker.saveFile(
        dialogTitle: 'Salvar backup do GlopPlay',
        fileName: 'glopplayer-backup-$date.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        mimeType: 'application/json',
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup exportado com sucesso.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível exportar o backup: $error')),
      );
    } finally {
      if (mounted) setState(() => _handlingBackup = false);
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

    setState(() => _handlingBackup = true);
    try {
      final selection = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (selection == null) return;
      final bytes = await selection.readAsBytes();
      final backup = AppBackup.decode(utf8.decode(bytes));
      final result = await BackupRestoreService.importBackup(backup);
      if (!mounted) return;
      final playlistProvider = context.read<PlaylistProvider>();
      final favoritesController = context.read<FavoritesController>();
      await playlistProvider.loadPlaylists();
      await favoritesController.refresh();
      if (!mounted) return;

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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível restaurar o backup: $error')),
      );
    } finally {
      if (mounted) setState(() => _handlingBackup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // Sem backgroundColor explícito: usa o scaffoldBackgroundColor definido
      // em AppTheme.light/dark (que já respeita AMOLED e o colorScheme atual).
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          children: [
            Text(
              'Configurações',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 24),

            // Grupo: Aparência
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.palette_outlined,
                  title: 'Tema',
                  subtitle: 'Cores, modo claro/escuro',
                  onTap: () => Navigator.pushNamed(
                      context, '/pages/theme_settings_screen'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.tune_outlined,
                  title: 'Configurações adicionais',
                  subtitle: 'Player nos álbuns e transição entre músicas',
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/pages/additional_settings_screen',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Grupo: Armazenamento
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.storage_outlined,
                  title: 'Banco de dados local',
                  subtitle: 'Ver tamanho e limpar dados salvos',
                  onTap: () => Navigator.pushNamed(
                      context, '/pages/cache_management_screen'),
                ),
                _SettingsTile(
                  icon: Icons.folder_open_outlined,
                  title: 'Pasta de músicas',
                  subtitle: 'Selecionar onde suas músicas ficam salvas',
                  onTap: () => Navigator.pushNamed(
                      context, '/pages/local_library_screen'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Grupo: Backup
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.file_upload_outlined,
                  title: 'Exportar dados',
                  subtitle: 'Salvar playlists e favoritos em um arquivo JSON',
                  onTap: _handlingBackup ? null : _exportBackup,
                  showArrow: !_handlingBackup,
                  isLoading: _handlingBackup,
                ),
                _SettingsTile(
                  icon: Icons.file_download_outlined,
                  title: 'Importar dados',
                  subtitle: 'Restaurar playlists e favoritos de um backup',
                  onTap: _handlingBackup ? null : _importBackup,
                  showArrow: !_handlingBackup,
                  isLoading: _handlingBackup,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Grupo: Sobre
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.info_outline,
                  title: 'Versão do app',
                  subtitle: _appVersion.isEmpty ? 'Carregando...' : _appVersion,
                  showArrow: false,
                ),
                _SettingsTile(
                  icon: Icons.system_update_outlined,
                  title: 'Verificar atualizações',
                  subtitle: _checkingUpdate
                      ? 'Verificando...'
                      : 'Checar se há uma nova versão disponível',
                  onTap: _checkingUpdate ? null : _checkForUpdatesManually,
                  showArrow: !_checkingUpdate,
                  isLoading: _checkingUpdate,
                ),
                _SettingsTile(
                  icon: Icons.article_outlined,
                  title: 'Logs',
                  subtitle: 'Ver logs do app para depuração',
                  onTap: () =>
                      Navigator.pushNamed(context, '/pages/logs_screen'),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// Card arredondado que agrupa vários _SettingsTile,
/// com divisores finos entre os itens (igual ao print de referência).
/// As cores vêm do ColorScheme ativo, então acompanham tema dinâmico,
/// seed color e modo claro/escuro/AMOLED automaticamente.
class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 68,
                color: cs.outlineVariant.withOpacity(0.3),
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool showArrow;
  final bool isLoading;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.showArrow = true,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                      color: cs.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isLoading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.onSurfaceVariant,
                ),
              )
            else if (showArrow)
              Icon(
                Icons.chevron_right,
                color: cs.onSurfaceVariant,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}
