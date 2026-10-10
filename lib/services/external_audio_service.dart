import 'package:flutter/services.dart';

class ExternalAudioService {
  ExternalAudioService._();

  static const MethodChannel _methodChannel = MethodChannel(
    'glopplayer/external_audio',
  );
  static const EventChannel _eventChannel = EventChannel(
    'glopplayer/external_audio/events',
  );

  static Stream<String> get audioUris =>
      _eventChannel.receiveBroadcastStream().map((event) {
        if (event is! String || event.isEmpty) {
          throw const FormatException('URI de áudio externo inválida');
        }
        return event;
      });

  static Future<String?> getInitialAudioUri() {
    return _methodChannel.invokeMethod<String>('getInitialAudio');
  }

  static Future<String> copyToCache(String uri) async {
    final path = await _methodChannel.invokeMethod<String>('copyAudioToCache', {
      'uri': uri,
    });
    if (path == null || path.isEmpty) {
      throw StateError(
        'O Android não retornou o caminho do áudio compartilhado',
      );
    }
    return path;
  }
}
