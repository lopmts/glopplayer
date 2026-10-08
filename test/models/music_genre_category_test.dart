import 'package:flutter_test/flutter_test.dart';
import 'package:glopplayer/models/music_genre_category.dart';
import 'package:on_audio_query/on_audio_query.dart';

SongModel _song({
  required int id,
  required String path,
  String? genre,
}) {
  return SongModel({
    '_id': id,
    'title': 'Song $id',
    'artist': 'Artist $id',
    'album': 'Album',
    'album_id': 1,
    'genre': genre,
    '_data': path,
    'duration': 180000,
    'is_music': 1,
    'is_podcast': 0,
    'is_ringtone': 0,
    'is_alarm': 0,
    'is_notification': 0,
    'is_audiobook': 0,
  });
}

void main() {
  test('categories follow the music filters, including songs without genre',
      () {
    final songs = [
      _song(id: 1, path: '/music/one.mp3', genre: 'Rock'),
      _song(id: 2, path: '/music/two.mp3', genre: ' rock '),
      _song(id: 3, path: '/music/three.mp3'),
      _song(id: 4, path: '/other/four.mp3', genre: 'Jazz'),
    ];

    final categories = MusicGenreCategory.fromSongs(songs);

    expect(
      categories.map((category) => category.name),
      ['Jazz', 'Rock', 'Sem gênero', 'rock'],
    );
    expect(categories[1].songs.map((song) => song.id), [1]);
    expect(categories[2].songs.map((song) => song.id), [3]);
    expect(categories[3].songs.map((song) => song.id), [2]);
  });

  test('categories respect the selected library folders', () {
    final songs = [
      _song(id: 1, path: '/music/one.mp3', genre: 'Rock'),
      _song(id: 2, path: '/other/two.mp3', genre: 'Jazz'),
    ];

    final categories = MusicGenreCategory.fromSongs(
      songs,
      folders: ['/music'],
    );

    expect(categories.map((category) => category.name), ['Rock']);
    expect(categories.single.songs.map((song) => song.id), [1]);
  });
}
