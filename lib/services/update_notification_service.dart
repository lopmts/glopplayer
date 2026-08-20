import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'update_service.dart';

/// Gerencia a notificação push do processo de atualização: barra de
/// progresso durante o download e mensagens específicas para cada
/// ocasião (iniciando, progresso, concluído, erro, cancelado).
///
/// Todas as atualizações reaproveitam o mesmo [_notificationId], então a
/// notificação é substituída/atualizada em vez de empilhar várias.
class UpdateNotificationService {
  UpdateNotificationService._internal();
  static final UpdateNotificationService instance =
      UpdateNotificationService._internal();

  static const int _notificationId = 9002;
  static const String _channelId = 'app_update_channel';
  static const String _channelName = 'Atualizações do app';
  static const String _channelDescription =
      'Progresso de download e status de atualizações do app';

  /// Payload usado para identificar o toque na notificação de "concluído".
  static const String _installPayload = 'install_update';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // Guarda a Future do init em vez de um bool. Assim, se alguma notificação
  // for pedida ANTES do init() (chamado sem await lá no main()) terminar,
  // a gente espera essa mesma Future em vez de simplesmente desistir — era
  // exatamente isso que fazia a notificação sumir em silêncio.
  Future<void>? _initFuture;
  String? _pendingInstallPath;

  /// Chame uma vez, no início do app (ex: `main()`). Pode ser sem `await`
  /// — é seguro chamar de novo depois, ou de vários lugares: a segunda
  /// chamada só reaproveita a Future da primeira.
  Future<void> init() {
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance:
            Importance.low, // evita som/vibração a cada tick de progresso
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  /// Garante que o init terminou antes de tentar mostrar uma notificação.
  /// Retorna false (sem propagar erro) se o init falhar — nesse caso a
  /// notificação simplesmente não aparece, mas o fluxo de update continua.
  Future<bool> _ensureInitialized() async {
    try {
      await init();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Pede permissão de notificação (obrigatório no Android 13+ e no iOS).
  /// Chame depois de `init()`, idealmente perto de quando o update começa
  /// (não precisa pedir isso no primeiro frame do app).
  Future<bool> requestPermissions() async {
    await _ensureInitialized();

    if (Platform.isAndroid) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return granted ?? false;
    }
    if (Platform.isIOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    return true;
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload == _installPayload && _pendingInstallPath != null) {
      // Usuário tocou na notificação de "download concluído": abre o instalador.
      UpdateService.instance.installApk(_pendingInstallPath!);
    }
  }

  AndroidNotificationDetails _androidDetails({
    required Importance importance,
    bool ongoing = false,
    bool autoCancel = true,
    bool showProgress = false,
    int progress = 0,
    bool indeterminate = false,
  }) {
    return AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: importance,
      priority: importance == Importance.high ? Priority.high : Priority.low,
      onlyAlertOnce: true,
      ongoing: ongoing,
      autoCancel: autoCancel,
      showProgress: showProgress,
      maxProgress: 100,
      progress: progress,
      indeterminate: indeterminate,
      icon: '@mipmap/ic_launcher',
      category: AndroidNotificationCategory.progress,
    );
  }

  /// "Verificando atualizações..." — opcional, útil se a checagem demorar
  /// (ex: disparada por um botão manual em vez de silenciosa no startup).
  Future<void> notifyChecking() async {
    if (!await _ensureInitialized()) return;
    await _plugin.show(
      id: _notificationId,
      title: 'Verificando atualizações',
      body: 'Consultando a última versão disponível...',
      notificationDetails: NotificationDetails(
        android: _androidDetails(
          importance: Importance.low,
          ongoing: true,
          autoCancel: false,
          indeterminate: true,
        ),
      ),
    );
  }

  /// Download começou (0%, indeterminado até o primeiro chunk chegar).
  Future<void> notifyDownloadStarted(String version) async {
    if (!await _ensureInitialized()) return;
    await _plugin.show(
      id: _notificationId,
      title: 'Baixando atualização',
      body: 'Versão $version — iniciando download...',
      notificationDetails: NotificationDetails(
        android: _androidDetails(
          importance: Importance.low,
          ongoing: true,
          autoCancel: false,
          showProgress: true,
          progress: 0,
          indeterminate: true,
        ),
      ),
    );
  }

  /// Atualiza a barra de progresso. Chame só quando a % inteira mudar,
  /// pra não estourar a taxa de atualização de notificações do Android.
  Future<void> updateProgress({
    required int percent,
    required String receivedMb,
    required String totalMb,
  }) async {
    if (!await _ensureInitialized()) return;
    await _plugin.show(
      id: _notificationId,
      title: 'Baixando atualização',
      body: '$percent%  •  $receivedMb MB / $totalMb MB',
      notificationDetails: NotificationDetails(
        android: _androidDetails(
          importance: Importance.low,
          ongoing: true,
          autoCancel: false,
          showProgress: true,
          progress: percent,
        ),
      ),
    );
  }

  /// Download concluído — notificação clicável que dispara a instalação.
  Future<void> notifyDownloadComplete({
    required String version,
    required String filePath,
  }) async {
    if (!await _ensureInitialized()) return;
    _pendingInstallPath = filePath;
    await _plugin.show(
      id: _notificationId,
      title: 'Download concluído',
      body: 'Versão $version pronta. Toque para instalar.',
      notificationDetails: NotificationDetails(
        android: _androidDetails(
          importance: Importance.high,
          ongoing: false,
          autoCancel: true,
        ),
      ),
      payload: _installPayload,
    );
  }

  /// Erro em qualquer etapa (checagem, download ou instalação).
  Future<void> notifyError(String message) async {
    if (!await _ensureInitialized()) return;
    await _plugin.show(
      id: _notificationId,
      title: 'Falha na atualização',
      body: message,
      notificationDetails: NotificationDetails(
        android: _androidDetails(
          importance: Importance.high,
          ongoing: false,
          autoCancel: true,
        ),
      ),
    );
  }

  /// Usuário cancelou o download manualmente.
  Future<void> notifyCancelled() async {
    if (!await _ensureInitialized()) return;
    await _plugin.show(
      id: _notificationId,
      title: 'Download cancelado',
      body: 'A atualização não foi baixada.',
      notificationDetails: NotificationDetails(
        android: _androidDetails(
          importance: Importance.low,
          ongoing: false,
          autoCancel: true,
        ),
      ),
    );
  }

  /// Remove a notificação de update (ex: ao fechar o dialog manualmente).
  Future<void> cancelNotification() async {
    if (!await _ensureInitialized()) return;
    await _plugin.cancel(id: _notificationId);
  }
}
