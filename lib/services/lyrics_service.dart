import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// Sistema de letras 100% local — nunca faz requisição de rede.
///
/// Ordem de busca:
///   1) tag ID3v2 USLT embutida no próprio arquivo (hoje só MP3)
///   2) arquivo irmão `<mesmo nome>.lrc` ou `.txt` na mesma pasta
///
/// Retorna null se nada for encontrado — a UI (`LyricsSheet`) já trata
/// esse caso mostrando "Letra não disponível".
class LyricsService {
  LyricsService._();
  static final LyricsService instance = LyricsService._();

  Future<String?> fetch(SongModel song) async {
    final path = song.data;

    // content:// URIs (ex: fakeSongModelFromExternalUri) não dão acesso
    // a File nem a arquivos irmãos — sem suporte a letra local aqui.
    if (path.startsWith('content://')) return null;

    try {
      final embedded = await _Id3v2LyricsReader.readUslt(path);
      if (embedded != null && embedded.trim().isNotEmpty) {
        return LyricsFormatter.format(embedded);
      }
    } catch (e) {
      debugPrint('Falha ao extrair letra embutida de "$path": $e');
    }

    final sidecar = await _readSidecar(path);
    if (sidecar != null) return LyricsFormatter.format(sidecar);

    return null;
  }

  Future<String?> _readSidecar(String audioPath) async {
    final dotIndex = audioPath.lastIndexOf('.');
    final base = dotIndex > 0 ? audioPath.substring(0, dotIndex) : audioPath;

    for (final ext in ['.lrc', '.txt']) {
      final file = File('$base$ext');
      try {
        if (await file.exists()) {
          final content = await file.readAsString();
          if (content.trim().isNotEmpty) return content;
        }
      } catch (e) {
        debugPrint('Erro ao ler letra sidecar "$base$ext": $e');
      }
    }
    return null;
  }
}

/// Limpa um texto LRC/TXT pra exibição: remove timestamps, remove linhas
/// de metadado ([ar:...], [ti:...] etc), preserva quebras de estrofe
/// (mas nunca deixa duas linhas em branco seguidas).
class LyricsFormatter {
  static final _timeTag = RegExp(r'^\[\d{2}:\d{2}(?:\.\d{1,3})?\]');
  static final _metaTag = RegExp(r'^\[[a-zA-Z]+:.*?\]$');

  static String format(String raw) {
    final rawLines = raw.split(RegExp(r'\r\n|\r|\n'));
    final out = <String>[];

    for (final line in rawLines) {
      final trimmed = line.trim();
      if (_metaTag.hasMatch(trimmed)) continue;

      var text = trimmed;
      while (_timeTag.hasMatch(text)) {
        text = text.replaceFirst(_timeTag, '').trimLeft();
      }

      if (text.isEmpty) {
        if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
        continue;
      }
      out.add(text);
    }

    while (out.isNotEmpty && out.first.isEmpty) out.removeAt(0);
    while (out.isNotEmpty && out.last.isEmpty) out.removeLast();
    return out.join('\n');
  }
}

/// Leitor mínimo de ID3v2 USLT (letra não sincronizada). Lê só o cabeçalho
/// da tag ID3 (10 bytes) + o corpo da tag (tagSize, geralmente poucos KB a
/// poucos MB se tiver capa embutida) — nunca o arquivo de áudio inteiro.
class _Id3v2LyricsReader {
  static Future<String?> readUslt(String path) async {
    RandomAccessFile? raf;
    try {
      raf = await File(path).open();
      final header = await raf.read(10);
      if (header.length < 10 ||
          header[0] != 0x49 ||
          header[1] != 0x44 ||
          header[2] != 0x33) {
        return null; // não começa com "ID3" -> sem tag v2 (ou não é mp3)
      }

      final majorVersion = header[3];
      final headerFlags = header[5];
      final tagSize = _synchsafe(header.sublist(6, 10));
      if (tagSize <= 0) return null;

      final tagBody = await raf.read(tagSize);

      var offset = 0;
      final hasExtendedHeader = (headerFlags & 0x40) != 0;
      if (hasExtendedHeader && tagBody.length >= 4) {
        final extSize = majorVersion >= 4
            ? _synchsafe(tagBody.sublist(0, 4))
            : _bigEndian(tagBody.sublist(0, 4));
        offset = extSize.clamp(0, tagBody.length);
      }

      while (offset + 10 <= tagBody.length) {
        final idBytes = tagBody.sublist(offset, offset + 4);
        if (idBytes[0] == 0) break; // entrou na área de padding

        final frameId = String.fromCharCodes(idBytes);
        final sizeBytes = tagBody.sublist(offset + 4, offset + 8);
        final frameSize =
            majorVersion >= 4 ? _synchsafe(sizeBytes) : _bigEndian(sizeBytes);
        offset += 10;

        if (frameSize <= 0 || offset + frameSize > tagBody.length) break;

        if (frameId == 'USLT') {
          final text = _decodeUslt(tagBody.sublist(offset, offset + frameSize));
          if (text != null && text.trim().isNotEmpty) return text.trim();
        }

        offset += frameSize;
      }
      return null;
    } catch (e) {
      debugPrint('Erro ao ler USLT de "$path": $e');
      return null;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  static int _synchsafe(List<int> b) =>
      (b[0] & 0x7F) << 21 |
      (b[1] & 0x7F) << 14 |
      (b[2] & 0x7F) << 7 |
      (b[3] & 0x7F);

  static int _bigEndian(List<int> b) =>
      (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];

  /// Frame USLT: 1 byte de encoding + 3 bytes de idioma ("por", "eng"...)
  /// + descrição curta terminada em null + o texto da letra em si.
  static String? _decodeUslt(List<int> data) {
    if (data.length < 5) return null;
    final encoding = data[0];
    final isUtf16 = encoding == 1 || encoding == 2;
    final nullLen = isUtf16 ? 2 : 1;

    var descEnd = 4; // pula encoding (1) + idioma (3)
    while (descEnd + nullLen <= data.length) {
      final isNull = nullLen == 1
          ? data[descEnd] == 0
          : data[descEnd] == 0 && data[descEnd + 1] == 0;
      if (isNull) break;
      descEnd += 1;
    }
    final textStart = (descEnd + nullLen).clamp(0, data.length);
    if (textStart >= data.length) return null;
    final textBytes = data.sublist(textStart);

    try {
      switch (encoding) {
        case 0:
          return latin1.decode(textBytes, allowInvalid: true);
        case 3:
          return utf8.decode(textBytes, allowMalformed: true);
        case 1:
        case 2:
          return _decodeUtf16(textBytes, hasBom: encoding == 1);
        default:
          return latin1.decode(textBytes, allowInvalid: true);
      }
    } catch (_) {
      return null;
    }
  }

  static String _decodeUtf16(List<int> bytes, {required bool hasBom}) {
    var b = bytes;
    var bigEndian = true;
    if (hasBom && b.length >= 2) {
      if (b[0] == 0xFF && b[1] == 0xFE) {
        bigEndian = false;
        b = b.sublist(2);
      } else if (b[0] == 0xFE && b[1] == 0xFF) {
        b = b.sublist(2);
      }
    }
    final units = <int>[];
    for (var i = 0; i + 1 < b.length; i += 2) {
      final unit = bigEndian ? (b[i] << 8) | b[i + 1] : (b[i + 1] << 8) | b[i];
      if (unit == 0) break;
      units.add(unit);
    }
    return String.fromCharCodes(units);
  }
}
