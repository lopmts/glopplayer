import 'package:flutter/material.dart';
import 'package:glopplayer/db/playlist_db.dart';
import 'package:glopplayer/models/playlist_models.dart';
import 'package:on_audio_query/on_audio_query.dart';

class PlaylistProvider extends ChangeNotifier {
  List<Playlist> _playlists = [];
  Playlist? _currentPlaylist;

  List<Playlist> get playlists => _playlists;
  Playlist? get currentPlaylist => _currentPlaylist;

  Future<void> loadPlaylists() async {
    _playlists = await PlaylistDB.getAllPlaylists();
    notifyListeners();
  }

  Future<void> createPlaylist(String name) async {
    if (name.trim().isEmpty) return;

    await PlaylistDB.createPlaylist(name.trim());
    await loadPlaylists();
  }

  Future<void> renamePlaylist(int id, String newName) async {
    await PlaylistDB.updatePlaylistName(id, newName.trim());
    await loadPlaylists();
  }

  Future<void> deletePlaylist(int id) async {
    await PlaylistDB.deletePlaylist(id);
    if (_currentPlaylist?.id == id) {
      _currentPlaylist = null;
    }
    await loadPlaylists();
  }

  Future<void> addSongToPlaylist(int playlistId, SongModel song) async {
    await PlaylistDB.addSongToPlaylist(playlistId, song);
    await loadPlaylists(); // recarrega do banco -> isInPlaylist fica correto
  }

  Future<void> removeSongFromPlaylist(int playlistId, int songId) async {
    await PlaylistDB.removeSongFromPlaylist(playlistId, songId);
    await loadPlaylists();

    if (_currentPlaylist?.id == playlistId) {
      _currentPlaylist = await PlaylistDB.getPlaylist(playlistId);
    }
    notifyListeners();
  }

  Future<void> selectPlaylist(int id) async {
    _currentPlaylist = await PlaylistDB.getPlaylist(id);
    notifyListeners();
  }

  void clearCurrentPlaylist() {
    _currentPlaylist = null;
    notifyListeners();
  }

  Future<void> removeSongFromAllPlaylists(int songId) async {
    final affected = _playlists
        .where((p) => p.songs.any((s) => s.songId == songId))
        .toList();

    for (final playlist in affected) {
      await PlaylistDB.removeSongFromPlaylist(playlist.id, songId);
    }

    if (affected.isEmpty) return;

    await loadPlaylists();

    if (_currentPlaylist != null &&
        affected.any((p) => p.id == _currentPlaylist!.id)) {
      _currentPlaylist = await PlaylistDB.getPlaylist(_currentPlaylist!.id);
    }
    notifyListeners();
  }

  Future<int> getSongCount(int playlistId) async {
    return await PlaylistDB.getPlaylistSongCount(playlistId);
  }

  Future<void> clearPlaylistSongs(int playlistId) async {
    await PlaylistDB.clearPlaylistSongs(playlistId);
    await loadPlaylists();

    if (_currentPlaylist?.id == playlistId) {
      _currentPlaylist = await PlaylistDB.getPlaylist(playlistId);
    }
    notifyListeners();
  }
}
