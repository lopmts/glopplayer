import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../utils/format_utils.dart';
import '../../utils/audio_type_utils.dart';

void showSongOptions(
  BuildContext context,
  SongModel song, {
  required VoidCallback onPlayNow,
  required VoidCallback onSelect,
  required VoidCallback onAddToPlaylist,
  required VoidCallback onEditMetadata,
}) {
  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.play_arrow),
            title: const Text('Tocar agora'),
            onTap: () {
              Navigator.pop(context);
              onPlayNow();
            },
          ),
          ListTile(
            leading: const Icon(Icons.check_box_outlined),
            title: const Text('Selecionar'),
            onTap: () {
              Navigator.pop(context);
              onSelect();
            },
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Adicionar à playlist'),
            onTap: () {
              Navigator.pop(context);
              onAddToPlaylist();
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Editar metadados'),
            onTap: () {
              Navigator.pop(context);
              onEditMetadata();
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Detalhes da música'),
            onTap: () {
              Navigator.pop(context);
              showSongDetailsDialog(context, song);
            },
          ),
        ],
      ),
    ),
  );
}

void showSongDetailsDialog(BuildContext context, SongModel song) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(song.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Artista: ${song.artist ?? "Desconhecido"}'),
          const SizedBox(height: 8),
          Text('Álbum: ${song.album ?? "Desconhecido"}'),
          const SizedBox(height: 8),
          Text(
              'Duração: ${formatDuration(Duration(milliseconds: song.duration ?? 0))}'),
          const SizedBox(height: 8),
          Text('Gênero: ${song.genre ?? "Desconhecido"}'),
          const SizedBox(height: 8),
          Text('Formato: ${audioTypeFromPath(song.data)}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}
