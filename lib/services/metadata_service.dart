import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_god/metadata_god.dart';
import 'package:mime/mime.dart';

/// Camada fina sobre o pacote `metadata_god` — centraliza toda leitura e
/// escrita de metadados (tags ID3/Vorbis/MP4 etc.) num único lugar, pra não
/// espalhar a dependência externa pelo resto do app.
///
/// IMPORTANTE: chame `MetadataService.init()` uma vez no `main.dart`, antes
/// do `runApp()` — a lib usa um binding Rust que precisa ser inicializado:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await MetadataService.init();
///   runApp(const MyApp());
/// }
/// ```
class MetadataService {
  MetadataService._();

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await MetadataGod.initialize();
    _initialized = true;
  }

  /// Lê os metadados atuais do arquivo. Retorna null se falhar (arquivo
  /// corrompido, formato não suportado, permissão negada etc.).
  static Future<Metadata?> read(String path) async {
    await init();
    try {
      return await MetadataGod.readMetadata(file: path);
    } catch (e, st) {
      // TEMPORÁRIO — precisa ver o que está acontecendo de verdade
      // ignore: avoid_print
      print('❌ metadata_god falhou em "$path": $e');
      return null;
    }
  }

  /// Grava um conjunto de campos, preservando tudo que não foi explicitamente
  /// passado. Como o `metadata_god` sobrescreve o arquivo inteiro a cada
  /// escrita, primeiro lemos o estado atual e mesclamos com o que veio aqui
  /// — senão campos não editados na tela seriam apagados.
  ///
  /// [overridePicture] define uma capa nova. [removePicture] força a
  /// remoção da capa (tem prioridade sobre [keepPicture]).
  static Future<bool> writeFields(
    String path, {
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? genre,
    int? year,
    int? trackNumber,
    int? trackTotal,
    int? discNumber,
    int? discTotal,
    bool keepPicture = true,
    Picture? overridePicture,
    bool removePicture = false,
  }) async {
    await init();
    final current = await read(path);

    final Picture? picture = removePicture
        ? null
        : (overridePicture ?? (keepPicture ? current?.picture : null));

    BigInt? fileSize;
    try {
      fileSize = BigInt.from(await File(path).length());
    } catch (_) {
      fileSize = current?.fileSize;
    }

    final metadata = Metadata(
      title: title ?? current?.title,
      artist: artist ?? current?.artist,
      album: album ?? current?.album,
      albumArtist: albumArtist ?? current?.albumArtist,
      genre: genre ?? current?.genre,
      year: year ?? current?.year,
      trackNumber: trackNumber ?? current?.trackNumber,
      trackTotal: trackTotal ?? current?.trackTotal,
      discNumber: discNumber ?? current?.discNumber,
      discTotal: discTotal ?? current?.discTotal,
      durationMs: current?.durationMs,
      fileSize: fileSize,
      picture: picture,
    );

    try {
      await MetadataGod.writeMetadata(file: path, metadata: metadata);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Extrai a capa embutida no arquivo (bytes brutos), se houver.
  static Future<Uint8List?> extractEmbeddedCover(String path) async {
    final meta = await read(path);
    return meta?.picture?.data;
  }

  /// Define a capa a partir de bytes crus (galeria, download etc).
  static Future<bool> setCoverFromBytes(
    String path,
    Uint8List bytes, {
    String? mimeType,
  }) {
    return writeFields(
      path,
      overridePicture: Picture(
        data: bytes,
        mimeType: mimeType ?? 'image/jpeg',
      ),
    );
  }

  /// Define a capa a partir de um arquivo de imagem local (ex: escolhido na
  /// galeria via image_picker).
  static Future<bool> setCoverFromFile(
      String path, String imageFilePath) async {
    final bytes = await File(imageFilePath).readAsBytes();
    final mime = lookupMimeType(imageFilePath) ?? 'image/jpeg';
    return setCoverFromBytes(path, bytes, mimeType: mime);
  }

  /// Remove qualquer capa embutida no arquivo.
  static Future<bool> removeCover(String path) {
    return writeFields(path, removePicture: true);
  }
}
