import 'package:flutter/material.dart';
import 'package:glopplayer/screens/albums_screen.dart';
import 'package:glopplayer/screens/home_screen.dart';
import 'package:glopplayer/screens/music_list_screen.dart';
import 'package:glopplayer/screens/pages/settings_screen.dart';
import 'package:glopplayer/screens/playlist_screen.dart';
import 'package:glopplayer/widgets/mini_player_bar.dart';

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const HomeScreen(),
    const PlaylistScreen(),
    const MusicListScreen(),
    const AlbumsScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: _pages[_selectedIndex],
      // MiniPlayerBar + bottom nav ficam juntos aqui. Como essa Scaffold
      // é a raiz das abas, qualquer tela empurrada por cima (ex: PlayerScreen)
      // cobre os dois automaticamente — nenhuma lógica extra necessária.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayerBar(),
            BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              type: BottomNavigationBarType.fixed,
              selectedItemColor: cs.primary,
              unselectedItemColor: cs.onSurfaceVariant,
              backgroundColor: cs.surfaceContainerHigh,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home),
                  label: 'Início',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.playlist_play_outlined),
                  label: 'PlayLists',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.library_music),
                  label: 'Músicas',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.album),
                  label: 'Álbuns',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings),
                  label: 'Configurações',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
