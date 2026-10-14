import 'package:flutter_test/flutter_test.dart';
import 'package:glopplayer/utils/lyrics_parser.dart';

void main() {
  group('LyricsParser', () {
    test('parses, sorts, and applies LRC offset to line timestamps', () {
      final parsed = LyricsParser.parse(
        '[ti:Example]\n[offset:500]\n'
        '[00:02.00]second line\n'
        '[00:01.00][00:03.00]repeated line',
      );

      expect(parsed.synced, isTrue);
      expect(parsed.lines.map((line) => line.text).toList(), [
        'repeated line',
        'second line',
        'repeated line',
      ]);
      expect(
        parsed.lines.map((line) => line.time.inMilliseconds).toList(),
        [500, 1500, 2500],
      );
      expect(LyricsParser.activeIndex(parsed.lines, const Duration(seconds: 2)),
          1);
    });

    test('parses enhanced LRC word timings and clean copy text', () {
      final parsed = LyricsParser.parse(
        '[00:00.00]<00:00.00>Hello <00:00.50>world',
      );

      expect(parsed.synced, isTrue);
      expect(parsed.wordSynced, isTrue);
      expect(parsed.lines.single.text, 'Hello world');
      expect(parsed.lines.single.words.map((word) => word.text).toList(), [
        'Hello ',
        'world',
      ]);
      expect(parsed.plainText, 'Hello world');
    });

    test('keeps plain text and removes metadata tags', () {
      final parsed = LyricsParser.parse('[ar:Artist]\nFirst line\n\nSecond');

      expect(parsed.synced, isFalse);
      expect(parsed.plainText, 'First line\nSecond');
      expect(parsed.lines, isEmpty);
    });
  });
}
