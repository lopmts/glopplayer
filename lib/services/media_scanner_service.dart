import 'package:flutter/services.dart';

/// Substitui o pacote `media_scanner` (abandonado, quebra o build com
/// AGP 9+/Kotlin embutido) por um MethodChannel próprio e minúsculo.
///
/// Avisa o MediaStore do Android que um arquivo mudou no disco — sem isso,
/// depois de reescrever as tags de uma música, o on_audio_query e o app de
/// galeria continuam mostrando o título/capa antigos em cache até o próximo
/// scan automático do sistema (que pode demorar).
///
/// Não faz nada no iOS/desktop (plataformas onde a chamada nativa não
/// existe) — falha em silêncio, então é seguro chamar sempre.
class MediaScannerService {
  MediaScannerService._();

  static const MethodChannel _channel =
      MethodChannel('glopplayer/media_scanner');

  static Future<void> scanFile(String path) async {
    try {
      await _channel.invokeMethod<void>('scanFile', {'path': path});
    } catch (_) {
      // Sem implementação nativa (ex: iOS) ou plataforma não suportada —
      // ignora, o rescan manual da biblioteca ainda resolve.
    }
  }
}
