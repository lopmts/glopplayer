import 'dart:convert';

import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Representa uma entrada no histórico de reprodução.
///
/// Guardamos os campos necessários pra reconstruir um [SongModel]
/// "mínimo" depois (título, artista, path, album/albumId) sem precisar
/// re-consultar o MediaStore — o que é importante porque o histórico
/// deve continuar funcionando mesmo se a música tiver sumido/mudado
/// de posição na biblioteca.
class RecentPlayEntry {
  final int songId;
  final String title;
  final String artist;
  final String data;
  final int? albumId;
  final String? album;
  final DateTime playedAt;

  RecentPlayEntry({
    required this.songId,
    required this.title,
    required this.artist,
    required this.data,
    required this.playedAt,
    this.albumId,
    this.album,
  });

  Map<String, dynamic> toJson() => {
        'songId': songId,
        'title': title,
        'artist': artist,
        'data': data,
        'albumId': albumId,
        'album': album,
        'playedAt': playedAt.toIso8601String(),
      };

  factory RecentPlayEntry.fromJson(Map<String, dynamic> json) {
    return RecentPlayEntry(
      songId: json['songId'] as int,
      title: (json['title'] as String?) ?? 'Sem título',
      artist: (json['artist'] as String?) ?? 'Artista desconhecido',
      data: (json['data'] as String?) ?? '',
      albumId: json['albumId'] as int?,
      album: json['album'] as String?,
      playedAt: DateTime.tryParse(json['playedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Reconstrói um [SongModel] "utilizável" a partir da entrada salva.
  /// Usado quando a música não está mais presente na varredura atual
  /// da biblioteca (ex: SD card desmontado, arquivo movido, etc.).
  SongModel toSongModel() {
    return SongModel({
      '_id': songId,
      'title': title,
      'artist': artist,
      'album': album,
      'album_id': albumId,
      '_data': data,
      'duration': null,
      'is_music': 1,
      'is_podcast': 0,
      'is_ringtone': 0,
      'is_alarm': 0,
      'is_notification': 0,
      'is_audiobook': 0,
    });
  }
}

/// Persiste e consulta o histórico de "tocadas recentemente".
///
/// Implementação simples baseada em SharedPreferences (uma única chave
/// com uma lista JSON) — suficiente pro tamanho do histórico (até
/// [maxEntries] itens). Se um dia precisar de mais volume/consultas,
/// dá pra trocar por uma tabela SQLite sem mudar a API pública.
class RecentlyPlayedService {
  static const _prefsKey = 'recently_played_songs_v1';
  static const int maxEntries = 60;

  List<RecentPlayEntry>? _cache;

  /// Retorna o histórico ordenado do mais recente pro mais antigo.
  Future<List<RecentPlayEntry>> getRecent() async {
    if (_cache != null) return _cache!;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      _cache = [];
      return _cache!;
    }

    try {
      final decoded = jsonDecode(raw) as List;
      _cache = decoded
          .map((e) => RecentPlayEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // JSON corrompido/versão antiga incompatível -> começa do zero
      _cache = [];
    }
    return _cache!;
  }

  /// Registra que [song] começou a tocar agora. Se a música já estava
  /// no histórico, ela é movida pro topo (sem duplicar).
  Future<void> recordPlay(SongModel song) async {
    if (song.id < 0) return; // ignora arquivos externos "fake" (id = -1)

    final entries = List<RecentPlayEntry>.from(await getRecent());
    entries.removeWhere((e) => e.songId == song.id);

    entries.insert(
      0,
      RecentPlayEntry(
        songId: song.id,
        title: song.title,
        artist: song.artist ?? 'Artista desconhecido',
        data: song.data,
        albumId: song.albumId,
        album: song.album,
        playedAt: DateTime.now(),
      ),
    );

    if (entries.length > maxEntries) {
      entries.removeRange(maxEntries, entries.length);
    }

    _cache = entries;
    await _persist(entries);
  }

  /// Remove uma música específica do histórico.
  Future<void> removeEntry(int songId) async {
    final entries = List<RecentPlayEntry>.from(await getRecent());
    entries.removeWhere((e) => e.songId == songId);
    _cache = entries;
    await _persist(entries);
  }

  /// Limpa todo o histórico de reprodução.
  Future<void> clear() async {
    _cache = [];
    await _persist([]);
  }

  Future<void> _persist(List<RecentPlayEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}
