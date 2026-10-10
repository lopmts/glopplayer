import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:glopplayer/controllers/favorites_controller.dart';
import 'package:glopplayer/screens/pages/favorites_screen.dart';
import 'package:glopplayer/screens/pages/log_screen.dart';
import 'package:glopplayer/screens/pages/player_screen.dart';
import 'package:home_widget/home_widget.dart';
import 'package:glopplayer/controllers/library_controller.dart';
import 'package:glopplayer/provider/playlist_provider.dart';
import 'package:glopplayer/provider/theme_provider.dart';
import 'package:glopplayer/screens/pages/cache_management_screen.dart';
import 'package:glopplayer/screens/pages/local_library_screen.dart';
import 'package:glopplayer/screens/pages/theme_settings_screen.dart';
import 'package:glopplayer/screens/pages/additional_settings_screen.dart';
import 'package:glopplayer/screens/pages/backup_settings_screen.dart';
import 'package:glopplayer/services/additional_settings_service.dart';
import 'package:glopplayer/services/external_audio_service.dart';
import 'package:glopplayer/services/metadata_service.dart';
import 'package:glopplayer/theme/dynamic_color_wrapper.dart';
import 'package:provider/provider.dart';
import 'package:glopplayer/widgets/tabs_navegation.dart';

import 'services/audio_player_handler.dart';
import 'controllers/player_controller.dart';

import 'package:glopplayer/widgets/update_dialog.dart';

late MyAudioHandler audioHandler;
late PlayerController playerController;

Future<void> _handleExternalAudioUri(String uri) async {
  try {
    await playerController.playExternalFile(uri);
  } catch (e, st) {
    debugPrint('Não foi possível abrir o áudio compartilhado: $e\n$st');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MetadataService.init();

  audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.glopplayer.channel.audio',
      androidNotificationChannelName: 'Reprodução de músicas Local',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  playerController = PlayerController(audioHandler);

  runApp(const MyApp());

  if (Platform.isAndroid) {
    ExternalAudioService.audioUris.listen(
      (uri) => unawaited(_handleExternalAudioUri(uri)),
      onError: (Object error) =>
          debugPrint('Erro ao receber áudio compartilhado: $error'),
    );
    final initialUri = await ExternalAudioService.getInitialAudioUri();
    if (initialUri != null) {
      await _handleExternalAudioUri(initialUri);
    } else {
      await playerController.restoreLastSession();
    }
  } else {
    final appLinks = AppLinks();
    final initialUri = await appLinks.getInitialLink();

    if (initialUri != null) {
      await _handleExternalAudioUri(initialUri.toString());
    } else {
      await playerController.restoreLastSession();
    }

    appLinks.uriLinkStream.listen(
      (uri) => unawaited(_handleExternalAudioUri(uri.toString())),
      onError: (err) => debugPrint('Erro na intent de áudio: $err'),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Navigator key used to obtain a BuildContext that is below MaterialApp
  // so dialogs (like the update dialog) can be shown safely on startup.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  StreamSubscription<Uri?>? _widgetSubscription;

  @override
  void initState() {
    super.initState();

    HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleWidgetUri);
    _widgetSubscription = HomeWidget.widgetClicked.listen(_handleWidgetUri);

    // Schedule a check for updates after the first frame so MaterialApp and
    // navigator are available. Uses the navigatorKey's context to show the
    // update dialog when an update is found.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = _navigatorKey.currentContext;
      if (ctx == null) return;
      try {
        await checkForUpdatesOnStartup(
          ctx,
          includePrerelease: false,
          onError: (err) => debugPrint('Erro ao checar atualizações: $err'),
        );
      } catch (e) {
        debugPrint('checkForUpdatesOnStartup failed: $e');
      }
    });
  }

  @override
  void dispose() {
    _widgetSubscription?.cancel();
    super.dispose();
  }

  void _handleWidgetUri(Uri? uri) {
    if (uri == null) return;
    final action = uri.host.isNotEmpty
        ? uri.host.toLowerCase()
        : uri.pathSegments.isNotEmpty
        ? uri.pathSegments.first.toLowerCase()
        : '';

    switch (action) {
      case 'playpause':
        playerController.playPause();
        break;
      case 'next':
        playerController.next();
        break;
      case 'previous':
        playerController.previous();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: playerController),
        ChangeNotifierProvider(
          create: (_) => PlaylistProvider()..loadPlaylists(),
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LibraryController()),
        ChangeNotifierProvider(create: (_) => FavoritesController()),
        ChangeNotifierProvider(
          create: (_) => AdditionalSettingsService()..load(),
        ),
      ],
      child: DynamicColorWrapper(
        builder: (context, lightTheme, darkTheme, mode) {
          return MaterialApp(
            navigatorKey: _navigatorKey,
            title: 'GlopPlay',
            debugShowCheckedModeBanner: false,
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: mode,
            home: const MainTabScreen(),
            routes: {
              '/pages/theme_settings_screen': (context) =>
                  const ThemeSettingsScreen(),
              '/pages/additional_settings_screen': (context) =>
                  const AdditionalSettingsScreen(),
              '/pages/backup_settings_screen': (context) =>
                  const BackupSettingsScreen(),
              '/pages/local_library_screen': (context) =>
                  const LocalLibraryScreen(),
              '/pages/player': (context) => const PlayerScreen(),
              '/pages/cache_management_screen': (context) =>
                  const CacheManagementScreen(),
              '/pages/logs_screen': (context) => const LogsScreen(),
              '/pages/favorites': (context) => FavoritesScreen(
                onSongTap: (song) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlayerScreen()),
                  );
                },
              ),
            },
          );
        },
      ),
    );
  }
}
