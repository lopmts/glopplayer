import 'package:flutter/material.dart';

Future<void> showSongFilterSheet(
  BuildContext context, {
  required List<String> artists,
  required List<String> genres,
  required List<String> types,
  required String? currentArtist,
  required String? currentGenre,
  required String? currentType,
  required void Function(String? artist, String? genre, String? type) onApply,
}) async {
  String? tempArtist = currentArtist;
  String? tempGenre = currentGenre;
  String? tempType = currentType;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Widget buildDropdown({
            required String label,
            required List<String> options,
            required String? value,
            required ValueChanged<String?> onChanged,
          }) {
            return DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: value,
              decoration: InputDecoration(
                labelText: label,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              hint: const Text('Todos'),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('Todos')),
                ...options.map(
                  (o) => DropdownMenuItem<String>(
                    value: o,
                    child: Text(o, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: onChanged,
            );
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Filtrar músicas',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: (tempArtist == null &&
                              tempGenre == null &&
                              tempType == null)
                          ? null
                          : () => setSheetState(() {
                                tempArtist = null;
                                tempGenre = null;
                                tempType = null;
                              }),
                      child: const Text('Limpar'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (artists.isNotEmpty) ...[
                  buildDropdown(
                    label: 'Artista',
                    options: artists,
                    value: tempArtist,
                    onChanged: (v) => setSheetState(() => tempArtist = v),
                  ),
                  const SizedBox(height: 12),
                ],
                if (genres.isNotEmpty) ...[
                  buildDropdown(
                    label: 'Gênero / tipo',
                    options: genres,
                    value: tempGenre,
                    onChanged: (v) => setSheetState(() => tempGenre = v),
                  ),
                  const SizedBox(height: 12),
                ],
                if (types.isNotEmpty)
                  buildDropdown(
                    label: 'Formato do arquivo',
                    options: types,
                    value: tempType,
                    onChanged: (v) => setSheetState(() => tempType = v),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    onApply(tempArtist, tempGenre, tempType);
                    Navigator.pop(sheetContext);
                  },
                  child: const Text('Aplicar filtros'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
