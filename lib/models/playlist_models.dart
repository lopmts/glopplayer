// playlist_models.dart
import 'package:on_audio_query/on_audio_query.dart';

class Playlist {
  final int id;
  final String name;
  final int? coverArtId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<PlaylistSong> songs;

  Playlist({
    required this.id,
    required this.name,
    this.coverArtId,
    required this.createdAt,
    required this.updatedAt,
    this.songs = const [],
  });

  factory Playlist.fromMap(Map<String, dynamic> map, List<PlaylistSong> songs) {
    return Playlist(
      id: map['id'] as int,
      name: map['name'] as String,
      coverArtId: map['cover_art_id'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      songs: songs,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'cover_art_id': coverArtId,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  Playlist copyWith({
    String? name,
    int? coverArtId,
    List<PlaylistSong>? songs,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      coverArtId: coverArtId ?? this.coverArtId,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      songs: songs ?? this.songs,
    );
  }
}

class PlaylistSong {
  final int id;
  final int playlistId;
  final int songId;
  final String title;
  final String? artist;
  final String? album;
  final int? duration;
  final DateTime addedAt;

  PlaylistSong({
    required this.id,
    required this.playlistId,
    required this.songId,
    required this.title,
    this.artist,
    this.album,
    this.duration,
    required this.addedAt,
  });

  factory PlaylistSong.fromMap(Map<String, dynamic> map) {
    return PlaylistSong(
      id: map['id'] as int,
      playlistId: map['playlist_id'] as int,
      songId: map['song_id'] as int,
      title: map['song_title'] as String,
      artist: map['song_artist'] as String?,
      album: map['song_album'] as String?,
      duration: map['song_duration'] as int?,
      addedAt: DateTime.fromMillisecondsSinceEpoch(map['added_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'playlist_id': playlistId,
      'song_id': songId,
      'song_title': title,
      'song_artist': artist,
      'song_album': album,
      'song_duration': duration,
      'added_at': addedAt.millisecondsSinceEpoch,
    };
  }
}
