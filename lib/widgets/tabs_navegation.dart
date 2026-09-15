import 'package:flutter/material.dart';
import 'package:glopplayer/screens/albums_screen.dart';
import 'package:glopplayer/screens/home_screen.dart';
import 'package:glopplayer/screens/music_list_screen.dart';
import 'package:glopplayer/screens/pages/settings_screen.dart';
import 'package:glopplayer/screens/playlist_screen.dart';
import 'package:glopplayer/services/additional_settings_service.dart';
import 'package:glopplayer/widgets/mini_player_bar.dart';
import 'package:provider/provider.dart';

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
            if (_selectedIndex != 3 ||
                context.watch<AdditionalSettingsService>().showPlayerOnAlbums)
              const MiniPlayerBar(),
            Material(
              color: cs.surfaceContainerHigh,
              child: Row(
                children: [
                  _TabItem(
                    icon: Icons.home_outlined,
                    selectedIcon: Icons.home,
                    label: 'Início',
                    selected: _selectedIndex == 0,
                    onTap: () => _selectTab(0),
                  ),
                  _TabItem(
                    icon: Icons.playlist_play_outlined,
                    selectedIcon: Icons.playlist_play,
                    label: 'Playlists',
                    selected: _selectedIndex == 1,
                    onTap: () => _selectTab(1),
                  ),
                  _TabItem(
                    icon: Icons.library_music_outlined,
                    selectedIcon: Icons.library_music,
                    label: 'Músicas',
                    selected: _selectedIndex == 2,
                    onTap: () => _selectTab(2),
                  ),
                  _TabItem(
                    icon: Icons.album_outlined,
                    selectedIcon: Icons.album,
                    label: 'Álbuns',
                    selected: _selectedIndex == 3,
                    onTap: () => _selectTab(3),
                  ),
                  _TabItem(
                    icon: Icons.settings_outlined,
                    selectedIcon: Icons.settings,
                    label: 'Configurações',
                    selected: _selectedIndex == 4,
                    onTap: () => _selectTab(4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectTab(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }
}

class _TabItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? cs.secondaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: RotationTransition(
                        turns: Tween<double>(begin: -0.08, end: 0).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutBack,
                          ),
                        ),
                        child: child,
                      ),
                    ),
                    child: Icon(
                      selected ? selectedIcon : icon,
                      key: ValueKey(selected),
                      color: selected
                          ? cs.onSecondaryContainer
                          : cs.onSurfaceVariant,
                      size: 23,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: selected
                              ? cs.onSecondaryContainer
                              : cs.onSurfaceVariant,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
