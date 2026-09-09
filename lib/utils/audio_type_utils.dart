/// Extrai e normaliza o "tipo" (formato) do arquivo de áudio a partir do
/// caminho, pra virar mais um filtro na lista de músicas (ex: MP3, FLAC,
/// M4A, OGG, WAV...). Não depende do metadata_god -- é só a extensão.
String audioTypeFromPath(String path) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == path.length - 1) return 'Desconhecido';

  final ext = path.substring(dotIndex + 1).toUpperCase();

  // Normaliza variações que na prática são o mesmo formato, pra não
  // duplicar entradas no dropdown (ex: .mp4 de áudio puro vs .m4a).
  switch (ext) {
    case 'M4A':
    case 'MP4':
      return 'M4A';
    case 'OGG':
    case 'OGA':
      return 'OGG';
    default:
      return ext.isEmpty ? 'Desconhecido' : ext;
  }
}
