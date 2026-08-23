import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glopplayer/models/update_models.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'update_notification_service.dart';

/// Status possível de uma checagem de atualização.
enum UpdateCheckStatus { upToDate, updateAvailable, error }

/// Resultado de [UpdateService.checkForUpdate].
class UpdateCheckResult {
  final UpdateCheckStatus status;
  final AppRelease? release;
  final String? currentVersion;
  final String? error;

  UpdateCheckResult({
    required this.status,
    this.release,
    this.currentVersion,
    this.error,
  });
}

/// Progresso de download, emitido durante [UpdateService.downloadApk].
class DownloadProgress {
  final int received;
  final int total; // pode ser 0 se o servidor não informar o content-length

  DownloadProgress({required this.received, required this.total});

  double get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;

  int get percent => (fraction * 100).round();

  String get receivedMb => (received / (1024 * 1024)).toStringAsFixed(1);

  String get totalMb => (total / (1024 * 1024)).toStringAsFixed(1);
}

/// Lançada quando o usuário cancela um download em andamento.
class UpdateCancelledException implements Exception {
  @override
  String toString() => 'Download cancelado pelo usuário';
}

/// Serviço central de auto-update via GitHub Releases.
///
/// Fluxo esperado:
/// 1. `checkForUpdate()` -> compara versão atual (package_info) com a última
///    release do repositório configurado.
/// 2. Se houver update, mostrar `UpdateDialog` (ver update_dialog.dart) com
///    os dados de `AppRelease`.
/// 3. `downloadApk(release, onProgress: ...)` -> baixa o .apk anexado à
///    release, emitindo progresso.
/// 4. `installApk(path)` -> abre o instalador nativo do Android.
class UpdateService {
  UpdateService._internal();
  static final UpdateService instance = UpdateService._internal();

  static const String owner = 'lopmts';
  static const String repo = 'glopplayer';

  /// Timeout para a checagem de release (chamada leve à API do GitHub).
  static const Duration _checkTimeout = Duration(seconds: 15);

  bool _cancelRequested = false;

  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();

  /// Stream global de progresso, útil se algo além do dialog quiser ouvir.
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  /// Consulta a última release (ou a lista completa, se [includePrerelease])
  /// e compara com a versão instalada via package_info_plus.
  Future<UpdateCheckResult> checkForUpdate({
    bool includePrerelease = false,
  }) async {
    String? currentVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      currentVersion = info.version;

      final uri = includePrerelease
          ? Uri.parse('https://api.github.com/repos/$owner/$repo/releases')
          : Uri.parse(
              'https://api.github.com/repos/$owner/$repo/releases/latest');

      final response = await http.get(uri, headers: const {
        'Accept': 'application/vnd.github+json'
      }).timeout(_checkTimeout);

      if (response.statusCode == 404) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.error,
          currentVersion: currentVersion,
          error: 'Nenhuma release encontrada no repositório $owner/$repo.',
        );
      }

      if (response.statusCode != 200) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.error,
          currentVersion: currentVersion,
          error: 'GitHub retornou HTTP ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);
      Map<String, dynamic> releaseJson;

      if (includePrerelease) {
        final list = (decoded as List<dynamic>).cast<Map<String, dynamic>>();
        if (list.isEmpty) {
          return UpdateCheckResult(
            status: UpdateCheckStatus.upToDate,
            currentVersion: currentVersion,
          );
        }
        releaseJson = list.first;
      } else {
        releaseJson = decoded as Map<String, dynamic>;
      }

      final release = AppRelease.fromJson(releaseJson);

      if (release.apkAsset == null) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.error,
          currentVersion: currentVersion,
          release: release,
          error: 'A release ${release.tagName} não tem um .apk anexado.',
        );
      }

      final isNewer = compareVersions(release.version, currentVersion) > 0;

      return UpdateCheckResult(
        status: isNewer
            ? UpdateCheckStatus.updateAvailable
            : UpdateCheckStatus.upToDate,
        release: release,
        currentVersion: currentVersion,
      );
    } on TimeoutException {
      return UpdateCheckResult(
        status: UpdateCheckStatus.error,
        currentVersion: currentVersion,
        error: 'Tempo esgotado ao consultar o GitHub. Verifique sua conexão.',
      );
    } on SocketException {
      return UpdateCheckResult(
        status: UpdateCheckStatus.error,
        currentVersion: currentVersion,
        error: 'Sem conexão com a internet.',
      );
    } catch (e) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.error,
        currentVersion: currentVersion,
        error: 'Falha ao checar atualização: $e',
      );
    }
  }

  /// Sinaliza para o download em andamento que deve ser interrompido.
  void cancelDownload() => _cancelRequested = true;

  /// Baixa o .apk da release para o diretório temporário do app,
  /// emitindo progresso via [onProgress] e via [progressStream].
  ///
  /// Lança [UpdateCancelledException] se `cancelDownload()` for chamado
  /// durante o download.
  Future<String> downloadApk(
    AppRelease release, {
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final asset = release.apkAsset;
    if (asset == null) {
      throw Exception('Release ${release.tagName} não possui um .apk.');
    }

    _cancelRequested = false;

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/glopplayer_${release.version}.apk';
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }

    final notifications = UpdateNotificationService.instance;
    await notifications.notifyDownloadStarted(release.version);

    final client = http.Client();
    IOSink? sink;
    var lastNotifiedPercent = -1;

    try {
      final request = http.Request('GET', Uri.parse(asset.downloadUrl));
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception(
          'Falha no download: HTTP ${streamedResponse.statusCode}.',
        );
      }

      final total = streamedResponse.contentLength ?? asset.size;
      var received = 0;
      sink = file.openWrite();

      await for (final chunk in streamedResponse.stream) {
        if (_cancelRequested) {
          throw UpdateCancelledException();
        }
        received += chunk.length;
        sink.add(chunk);

        final progress = DownloadProgress(received: received, total: total);
        onProgress?.call(progress);
        _progressController.add(progress);

        // Só atualiza a notificação quando a % inteira muda, pra não
        // estourar a taxa de atualização de notificações do Android.
        if (total > 0 && progress.percent != lastNotifiedPercent) {
          lastNotifiedPercent = progress.percent;
          unawaited(notifications.updateProgress(
            percent: progress.percent,
            receivedMb: progress.receivedMb,
            totalMb: progress.totalMb,
          ));
        }
      }

      await notifications.notifyDownloadComplete(
        version: release.version,
        filePath: filePath,
      );

      return filePath;
    } on UpdateCancelledException {
      await _safeDelete(file);
      await notifications.notifyCancelled();
      rethrow;
    } catch (e) {
      await _safeDelete(file);
      final message = e is UpdateCancelledException
          ? e.toString()
          : 'Erro durante o download: $e';
      await notifications.notifyError(message);
      if (e is UpdateCancelledException) rethrow;
      throw Exception(message);
    } finally {
      await sink?.close();
      client.close();
    }
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // ignora falha ao limpar arquivo parcial
    }
  }

  /// Abre o instalador nativo do Android para o apk baixado.
  /// Requer a permissão REQUEST_INSTALL_PACKAGES no AndroidManifest.xml
  /// (ver instruções no final de update_dialog.dart).
  Future<void> installApk(String filePath) async {
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      throw Exception(
        'Não foi possível abrir o instalador (${result.type}): '
        '${result.message}',
      );
    }
  }

  void dispose() {
    _progressController.close();
  }
}
