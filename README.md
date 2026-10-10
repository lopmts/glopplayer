# Simple Music Player (Flutter)

App de player de música local no Android, com:
- **Leitura automática de toda a biblioteca do aparelho** (músicas e álbuns),
  via `on_audio_query_forked` (consulta direta ao MediaStore do Android) —
  não é mais necessário selecionar arquivo por arquivo.
- Capas de álbum, título e artista lidos diretamente dos metadados do MediaStore.
- Áudios podem ser abertos pelo menu **Abrir com** ou compartilhados de outros
  apps; título, artista, álbum, duração e capa incorporada são lidos do arquivo
  antes de iniciar a reprodução.
- Duas abas: **Músicas** (lista completa) e **Álbuns** (grade com capas).
- Tela de álbum mostrando só as músicas daquele álbum.
- Tela de player com capa, play/pause, próxima/anterior e barra de progresso (seek).

## Como rodar

1. **Crie o projeto Flutter base:**
   ```bash
   flutter create simple_music_player
   ```

2. **Copie os arquivos deste pacote por cima do projeto criado** (para
   DENTRO da pasta que o `flutter create` gerou — a que já tem `android/`,
   `ios/`, `pubspec.lock`), sobrescrevendo:
   - `lib/` (inteira)
   - `pubspec.yaml`
   - `android/app/src/main/AndroidManifest.xml`

3. **Instale as dependências:**
   ```bash
   flutter pub get
   ```

4. **Rode no dispositivo Android** (emulador não tem músicas reais, use um
   aparelho físico ou copie arquivos de áudio para o armazenamento do emulador):
   ```bash
   flutter run
   ```

5. Na primeira abertura, o app vai pedir permissão de acesso à biblioteca de
   áudio. Aceite para ver as músicas do aparelho.

## Estrutura

```
lib/
  main.dart                        # inicializa Provider e o app
  services/
    music_library_service.dart     # consulta músicas/álbuns via MediaStore
    player_controller.dart         # controla o AudioPlayer (play/pause/seek/next)
  screens/
    home_screen.dart               # abas "Músicas" e "Álbuns"
    album_songs_screen.dart        # músicas de um álbum específico
    player_screen.dart             # capa, progresso e controles
```

## Observações importantes

- No Android, o app recebe arquivos de áudio por **VIEW** e **Compartilhar**.
  Arquivos `content://` são copiados para o cache privado do app para permitir
  a reprodução e a leitura das tags mesmo sem acesso direto ao caminho original.

- **`SongModel` e `AlbumModel`** vêm prontos do pacote `on_audio_query_forked`
  — não precisamos mais de um modelo `Song` próprio nem de extrair metadados
  manualmente. Eles já trazem `id`, `title`, `artist`, `album`, `duration`,
  `uri`, `albumId`, etc.
- **Capas de álbum** são exibidas com o widget `QueryArtworkWidget(id: ...,
  type: ArtworkType.AUDIO / ArtworkType.ALBUM)`, que busca a arte diretamente
  do MediaStore pelo id da música ou do álbum — muito mais eficiente do que
  ler bytes do arquivo manualmente.
- **Reprodução via `content://` URI** (`song.uri`) em vez do caminho de
  arquivo bruto (`song.data`) — mais confiável no Android 10+ com Scoped
  Storage.
- **Permissões:** `READ_MEDIA_AUDIO` (Android 13+) e `READ_EXTERNAL_STORAGE`
  (Android 12 ou anterior) já estão no `AndroidManifest.xml`. O pacote cuida
  do fluxo de solicitação via `checkAndRequest()`.
- Este app **não tem mais notificação de reprodução em segundo plano**
  (removemos o `just_audio_background` conforme seu ajuste). Se quiser
  recuperar a notificação com progresso/controles no futuro, dá pra
  reintroduzir o `just_audio_background` (ou migrar para `audio_service`
  completo) sem afetar a lógica de biblioteca/álbuns feita aqui.
- Próximos passos naturais: tela de artistas, busca/filtro por título,
  fila de reprodução visível, modo shuffle/repeat, favoritos.

## Testado com

- `just_audio: ^0.10.6`
- `audio_session: ^0.2.4`
- `on_audio_query_forked: ^2.9.1`
- `provider: ^6.1.2`
