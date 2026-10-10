import 'package:flutter_test/flutter_test.dart';
import 'package:glopplayer/services/music_library_service.dart';

void main() {
  group('fakeSongModelFromExternalUri', () {
    test('uses embedded audio metadata when available', () {
      final song = fakeSongModelFromExternalUri(
        '/cache/shared_audio/track.mp3',
        title: 'Tagged title',
        artist: 'Tagged artist',
        album: 'Tagged album',
        durationMs: 183456.0,
      );

      expect(song.data, '/cache/shared_audio/track.mp3');
      expect(song.title, 'Tagged title');
      expect(song.artist, 'Tagged artist');
      expect(song.album, 'Tagged album');
      expect(song.duration, 183456);
    });

    test('falls back to the local filename when tags are missing', () {
      final song = fakeSongModelFromExternalUri('/cache/audio/fallback.flac');

      expect(song.title, 'fallback.flac');
      expect(song.artist, 'Artista desconhecido');
      expect(song.album, 'Álbum desconhecido');
      expect(song.duration, isNull);
    });
  });
}
