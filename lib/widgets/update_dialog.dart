import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:glopplayer/models/update_models.dart';
import 'package:glopplayer/services/update_notification_service.dart';
import 'package:glopplayer/services/update_service.dart';

enum _DialogState { info, downloading, error, readyToInstall }

/// Modal de atualização do app.
///
/// Mostra as informações da release (versão, changelog), permite iniciar
/// o download com barra de progresso, trata erros com opção de retry e,
/// ao final, oferece o botão de instalar.
///
/// Uso:
/// ```dart
/// final result = await UpdateService.instance.checkForUpdate();
/// if (result.status == UpdateCheckStatus.updateAvailable && context.mounted) {
///   showUpdateDialog(context, result.release!, currentVersion: result.currentVersion);
/// }
/// ```
class UpdateDialog extends StatefulWidget {
  final AppRelease release;
  final String? currentVersion;

  /// Se true, o usuário não pode fechar o dialog tocando fora ou no "Agora não"
  /// (útil para updates obrigatórios).
  final bool forceUpdate;

  const UpdateDialog({
    super.key,
    required this.release,
    this.currentVersion,
    this.forceUpdate = false,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  _DialogState _state = _DialogState.info;
  DownloadProgress? _progress;
  String? _errorMessage;
  String? _downloadedPath;

  Future<void> _startDownload() async {
    setState(() {
      _state = _DialogState.downloading;
      _errorMessage = null;
      _progress = DownloadProgress(received: 0, total: 0);
    });

    // Pede permissão de notificação aqui (não no startup do app), pra pedir
    // no momento em que ela realmente importa. Falha em pedir não deve
    // travar o download — a notificação simplesmente não aparece.
    try {
      await UpdateNotificationService.instance.requestPermissions();
    } catch (_) {
      // segue o fluxo mesmo se a permissão for negada ou o plugin falhar
    }

    try {
      final path = await UpdateService.instance.downloadApk(
        widget.release,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );

      if (!mounted) return;
      setState(() {
        _downloadedPath = path;
        _state = _DialogState.readyToInstall;
      });
    } on UpdateCancelledException {
      if (!mounted) return;
      setState(() => _state = _DialogState.info);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _state = _DialogState.error;
      });
    }
  }

  void _cancelDownload() {
    UpdateService.instance.cancelDownload();
  }

  Future<void> _install() async {
    if (_downloadedPath == null) return;
    try {
      await UpdateService.instance.installApk(_downloadedPath!);
      // Não fechamos o dialog automaticamente: o instalador do Android
      // assume a tela. O usuário volta pro app se cancelar a instalação.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _state = _DialogState.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.forceUpdate && _state != _DialogState.downloading,
      child: AlertDialog(
        title: _buildTitle(),
        content: SizedBox(
          width: double.maxFinite,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _buildContent(),
          ),
        ),
        actions: _buildActions(context),
      ),
    );
  }

  Widget _buildTitle() {
    switch (_state) {
      case _DialogState.info:
        return const Text('Nova atualização disponível');
      case _DialogState.downloading:
        return const Text('Baixando atualização...');
      case _DialogState.error:
        return const Text('Falha na atualização');
      case _DialogState.readyToInstall:
        return const Text('Pronto para instalar');
    }
  }

  Widget _buildContent() {
    switch (_state) {
      case _DialogState.info:
        return _InfoContent(
          key: const ValueKey('info'),
          release: widget.release,
          currentVersion: widget.currentVersion,
        );
      case _DialogState.downloading:
        return _DownloadingContent(
          key: const ValueKey('downloading'),
          progress: _progress,
        );
      case _DialogState.error:
        return _ErrorContent(
          key: const ValueKey('error'),
          message: _errorMessage ?? 'Erro desconhecido.',
        );
      case _DialogState.readyToInstall:
        return _ReadyContent(
          key: const ValueKey('ready'),
          version: widget.release.version,
        );
    }
  }

  List<Widget> _buildActions(BuildContext context) {
    switch (_state) {
      case _DialogState.info:
        return [
          if (!widget.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Agora não'),
            ),
          FilledButton(
            onPressed: _startDownload,
            child: const Text('Atualizar'),
          ),
        ];

      case _DialogState.downloading:
        return [
          TextButton(
            onPressed: _cancelDownload,
            child: const Text('Cancelar'),
          ),
        ];

      case _DialogState.error:
        return [
          if (!widget.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          FilledButton(
            onPressed: () => setState(() => _state = _DialogState.info),
            child: const Text('Tentar novamente'),
          ),
        ];

      case _DialogState.readyToInstall:
        return [
          if (!widget.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Depois'),
            ),
          FilledButton(
            onPressed: _install,
            child: const Text('Instalar'),
          ),
        ];
    }
  }
}

class _InfoContent extends StatelessWidget {
  final AppRelease release;
  final String? currentVersion;

  const _InfoContent({super.key, required this.release, this.currentVersion});

  @override
  Widget build(BuildContext context) {
    final apk = release.apkAsset;
    final sizeMb =
        apk != null ? (apk.size / (1024 * 1024)).toStringAsFixed(1) : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (currentVersion != null) ...[
              Text(
                currentVersion!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward, size: 16),
              ),
            ],
            Text(
              release.version,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (sizeMb != null) ...[
              const Spacer(),
              Text(
                '$sizeMb MB',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (release.changelog.trim().isNotEmpty) ...[
          Text(
            'Novidades',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: SingleChildScrollView(
              child: MarkdownBody(
                data: release.changelog.trim(),
                styleSheet: MarkdownStyleSheet(
                  p: Theme.of(context).textTheme.bodyMedium,
                  // Customize other styles as needed
                ),
              ),
            ),
          ),
        ] else
          Text(
            'Sem notas de versão para esta release.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
      ],
    );
  }
}

class _DownloadingContent extends StatelessWidget {
  final DownloadProgress? progress;

  const _DownloadingContent({super.key, this.progress});

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final hasTotal = p != null && p.total > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: hasTotal
              ? p.fraction
              : null, // indeterminado se não souber o total
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              hasTotal
                  ? '${p.receivedMb} MB / ${p.totalMb} MB'
                  : (p != null
                      ? '${p.receivedMb} MB baixados'
                      : 'Iniciando...'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (hasTotal)
              Text(
                '${p.percent}%',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ],
    );
  }
}

class _ErrorContent extends StatelessWidget {
  final String message;

  const _ErrorContent({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            const Expanded(
                child: Text('Não foi possível concluir a atualização.')),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ],
    );
  }
}

class _ReadyContent extends StatelessWidget {
  final String version;

  const _ReadyContent({super.key, required this.version});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.check_circle, color: Colors.green.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Versão $version baixada. Toque em "Instalar" e confirme no '
            'instalador do Android.',
          ),
        ),
      ],
    );
  }
}

/// Abre o [UpdateDialog] para a release informada.
Future<void> showUpdateDialog(
  BuildContext context,
  AppRelease release, {
  String? currentVersion,
  bool forceUpdate = false,
}) {
  return showDialog(
    context: context,
    barrierDismissible: !forceUpdate,
    builder: (_) => UpdateDialog(
      release: release,
      currentVersion: currentVersion,
      forceUpdate: forceUpdate,
    ),
  );
}

/// Helper de conveniência: checa por atualização e, se houver, já abre o
/// dialog. Ideal para chamar no `initState` da tela principal (com um
/// `WidgetsBinding.instance.addPostFrameCallback` para ter um `context` válido).
///
/// Retorna `true` se um update foi encontrado (dialog aberto), `false` caso
/// contrário. Erros de checagem são silenciosos aqui por padrão — passe
/// [onError] se quiser tratá-los (ex: mostrar um SnackBar).
Future<bool> checkForUpdatesOnStartup(
  BuildContext context, {
  bool includePrerelease = false,
  void Function(String error)? onError,
}) async {
  final result = await UpdateService.instance
      .checkForUpdate(includePrerelease: includePrerelease);

  if (result.status == UpdateCheckStatus.error) {
    if (result.error != null) onError?.call(result.error!);
    return false;
  }

  if (result.status == UpdateCheckStatus.updateAvailable &&
      result.release != null &&
      context.mounted) {
    await showUpdateDialog(
      context,
      result.release!,
      currentVersion: result.currentVersion,
    );
    return true;
  }

  return false;
}
