import 'package:flutter/material.dart';
import 'package:glopplayer/widgets/create_playlist_dialog.dart';
import 'package:glopplayer/provider/playlist_provider.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';

class AddToPlaylistDialog extends StatelessWidget {
  final List<SongModel> songs;

  const AddToPlaylistDialog({super.key, required this.songs});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlaylistProvider>();

    return AlertDialog(
      title: Text(
        songs.length == 1
            ? 'Adicionar à Playlist'
            : 'Adicionar ${songs.length} músicas',
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: provider.playlists.isEmpty
            ? const Center(
                child: Text('Nenhuma playlist disponível'),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: provider.playlists.length,
                itemBuilder: (context, index) {
                  final playlist = provider.playlists[index];
                  final missing = songs
                      .where(
                          (s) => !playlist.songs.any((ps) => ps.songId == s.id))
                      .toList();
                  final allInPlaylist = missing.isEmpty;

                  return ListTile(
                    leading: Icon(
                      allInPlaylist ? Icons.check_circle : Icons.playlist_add,
                      color: allInPlaylist ? Colors.green : null,
                    ),
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.songs.length} músicas'),
                    onTap: allInPlaylist
                        ? null
                        : () async {
                            for (final song in missing) {
                              await context
                                  .read<PlaylistProvider>()
                                  .addSongToPlaylist(playlist.id, song);
                            }
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    missing.length == 1
                                        ? '"${missing.first.title}" adicionada à playlist'
                                        : '${missing.length} músicas adicionadas à playlist',
                                  ),
                                ),
                              );
                            }
                          },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            Future.microtask(() {
              showDialog(
                context: context,
                builder: (_) => const CreatePlaylistDialog(),
              );
            });
          },
          child: const Text('Criar Nova'),
        ),
      ],
    );
  }
}
