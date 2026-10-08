import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glopplayer/services/backup_restore_service.dart';

void main() {
  group('AppBackup.decode', () {
    test('decodes playlist songs and favorites', () {
      final backup = AppBackup.decode(jsonEncode({
        'format': AppBackup.formatName,
        'version': AppBackup.currentVersion,
        'playlists': [
          {
            'name': 'Favoritas para viagem',
            'cover_art_id': 7,
            'created_at': 100,
            'updated_at': 200,
            'songs': [
              {
                'song_id': 7,
                'title': 'Canção',
                'artist': 'Artista',
                'album': 'Álbum',
                'duration': 180000,
                'added_at': 150,
              },
            ],
          },
        ],
        'favorites': [
          {
            'song_id': 7,
            'title': 'Canção',
            'artist': 'Artista',
            'album': 'Álbum',
            'album_id': 3,
            'genre': 'Pop',
            'data': '/music/song.mp3',
            'favorited_at': '2025-01-01T12:00:00.000',
          },
        ],
      }));

      expect(backup.playlists.single['name'], 'Favoritas para viagem');
      expect(
        (backup.playlists.single['songs'] as List).single['song_id'],
        7,
      );
      expect(backup.favorites.single['genre'], 'Pop');

      final restored = AppBackup.decode(jsonEncode(backup.toMap()));
      expect(restored.playlists.single['name'], 'Favoritas para viagem');
      expect(restored.favorites.single['song_id'], 7);
    });

    test('rejects unsupported versions', () {
      expect(
        () => AppBackup.decode(jsonEncode({
          'format': AppBackup.formatName,
          'version': AppBackup.currentVersion + 1,
          'playlists': [],
          'favorites': [],
        })),
        throwsFormatException,
      );
    });

    test('rejects invalid playlist song identifiers', () {
      expect(
        () => AppBackup.decode(jsonEncode({
          'format': AppBackup.formatName,
          'version': AppBackup.currentVersion,
          'playlists': [
            {
              'name': 'Inválida',
              'created_at': 100,
              'updated_at': 100,
              'songs': [
                {
                  'song_id': -1,
                  'title': 'Canção',
                  'added_at': 100,
                },
              ],
            },
          ],
          'favorites': [],
        })),
        throwsFormatException,
      );
    });
  });
}
