import 'package:flutter/material.dart';
import 'package:glopplayer/controllers/player_controller.dart';
import 'package:glopplayer/services/additional_settings_service.dart';
import 'package:glopplayer/services/crossfade_settings_service.dart';
import 'package:provider/provider.dart';

class AdditionalSettingsScreen extends StatelessWidget {
  const AdditionalSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final additional = context.watch<AdditionalSettingsService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações adicionais')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Reprodução',
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _SettingsCard(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.queue_music_outlined),
                title: const Text('Mostrar player nos álbuns'),
                subtitle: const Text(
                  'Exibe a música atual dentro dos detalhes do álbum',
                ),
                value: additional.showPlayerOnAlbums,
                onChanged: additional.setShowPlayerOnAlbums,
              ),
              const Divider(height: 1, indent: 56),
              Consumer<PlayerController>(
                builder: (context, player, _) => AnimatedBuilder(
                  animation: player.crossfadeSettings,
                  builder: (context, _) {
                    final settings = player.crossfadeSettings;
                    return Column(
                      children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.graphic_eq_outlined),
                          title: const Text('Transição suave entre músicas'),
                          subtitle: const Text(
                            'Crossfade ao se aproximar do fim da faixa',
                          ),
                          value: settings.enabled,
                          onChanged: settings.setEnabled,
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          child: settings.enabled
                              ? Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Duração: ${settings.durationSeconds}s',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                      Slider(
                                        value:
                                            settings.durationSeconds.toDouble(),
                                        min: CrossfadeSettingsService.minSeconds
                                            .toDouble(),
                                        max: CrossfadeSettingsService.maxSeconds
                                            .toDouble(),
                                        divisions: CrossfadeSettingsService
                                                .maxSeconds -
                                            CrossfadeSettingsService.minSeconds,
                                        label: '${settings.durationSeconds}s',
                                        onChanged: (value) => settings
                                            .setDurationSeconds(value.round()),
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
