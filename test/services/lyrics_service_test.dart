import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glopplayer/services/lyrics_service.dart';
import 'package:glopplayer/utils/lyrics_parser.dart';
import 'package:on_audio_query/on_audio_query.dart';

SongModel _song(String path) => SongModel({
      '_id': 1,
      'title': 'Track',
      'artist': 'Artist',
      'album': 'Album',
      'album_id': 1,
      '_data': path,
      'duration': 180000,
      'is_music': 1,
      'is_podcast': 0,
      'is_ringtone': 0,
      'is_alarm': 0,
      'is_notification': 0,
      'is_audiobook': 0,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LyricsService', () {
    test('prefers and preserves timestamps from an LRC sidecar', () async {
      final directory = await Directory.systemTemp.createTemp('lyrics_test_');
      addTearDown(() => directory.delete(recursive: true));
      final audioFile =
          File('${directory.path}${Platform.pathSeparator}track.mp3');
      final lrcFile =
          File('${directory.path}${Platform.pathSeparator}track.lrc');
      const lrc = '[00:01.25]First line\n[00:03.50]Second line';
      await audioFile.create();
      await lrcFile.writeAsString(lrc);

      final raw = await LyricsService.instance.fetch(_song(audioFile.path));

      expect(raw, lrc);
      final parsed = LyricsParser.parse(raw);
      expect(parsed.synced, isTrue);
      expect(parsed.lines.first.time, const Duration(milliseconds: 1250));
    });

    test('uses a plain-text sidecar when no LRC sidecar exists', () async {
      final directory = await Directory.systemTemp.createTemp('lyrics_test_');
      addTearDown(() => directory.delete(recursive: true));
      final audioFile =
          File('${directory.path}${Platform.pathSeparator}track.mp3');
      await audioFile.create();
      await File('${directory.path}${Platform.pathSeparator}track.txt')
          .writeAsString('First line\nSecond line');

      final raw = await LyricsService.instance.fetch(_song(audioFile.path));

      expect(raw, 'First line\nSecond line');
      expect(LyricsParser.parse(raw).synced, isFalse);
    });
  });
}
