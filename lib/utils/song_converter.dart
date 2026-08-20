import 'package:glopplayer/models/playlist_models.dart';
import 'package:on_audio_query/on_audio_query.dart';

class SongConverter {
  static SongModel fromPlaylistSong(PlaylistSong playlistSong) {
    return SongModel({
      "_id": playlistSong.songId,
      "title": playlistSong.title,
      "artist": playlistSong.artist ?? '',
      "album": playlistSong.album ?? '',
      "duration": playlistSong.duration ?? 0,
      "_data": '', // caminho do arquivo
      "_display_name": playlistSong.title,
      "mime_type": '',
      "_size": -1,
      "track": 0,
      "year": 0,
      "date_modified": 0,
      "is_music": false,
      "is_alarm": false,
      "is_notification": false,
      "is_ringtone": false,
      "is_podcast": false,
      "is_audiobook": false,
    });
  }

  static List<SongModel> fromPlaylistSongs(List<PlaylistSong> playlistSongs) {
    return playlistSongs.map((ps) => fromPlaylistSong(ps)).toList();
  }
}
