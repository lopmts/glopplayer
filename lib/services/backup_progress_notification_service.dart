import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BackupProgressNotificationService {
  BackupProgressNotificationService._();

  static final instance = BackupProgressNotificationService._();

  static const _channelId = 'com.glopplayer.channel.backup';
  static const _channelName = 'Backup e restauração';
  static const _notificationId = 9002;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  Future<void> showIndeterminate({
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();
    await _plugin.show(
      id: _notificationId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Progresso da exportação e restauração de dados',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          ongoing: true,
          showProgress: true,
          indeterminate: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  Future<void> updateProgress({
    required String title,
    required int current,
    required int total,
  }) async {
    await _ensureInitialized();
    final maximum = total <= 0 ? 1 : total;
    final progress = current.clamp(0, maximum);
    await _plugin.show(
      id: _notificationId,
      title: title,
      body: '$current de $total itens',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Progresso da exportação e restauração de dados',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          ongoing: true,
          showProgress: true,
          indeterminate: false,
          maxProgress: maximum,
          progress: progress,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  Future<void> showCompleted({
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();
    await _plugin.show(
      id: _notificationId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Progresso da exportação e restauração de dados',
          importance: Importance.low,
          priority: Priority.low,
          autoCancel: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  Future<void> showFailed(String operation) async {
    await showCompleted(
      title: '$operation não concluída',
      body: 'Ocorreu um erro. Abra o GlopPlay para ver os detalhes.',
    );
  }

  Future<void> dismiss() async {
    await _ensureInitialized();
    await _plugin.cancel(id: _notificationId);
  }
}
