import 'package:flutter/material.dart';
import 'package:glopplayer/services/player_controller.dart';

class SpeedButton extends StatelessWidget {
  final PlayerController controller;
  const SpeedButton({super.key, required this.controller});

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<double>(
      stream: controller.player.speedStream,
      builder: (context, snapshot) {
        final speed = snapshot.data ?? 1.0;
        return PopupMenuButton<double>(
          initialValue: speed,
          tooltip: 'Velocidade',
          color: scheme.surfaceContainerHigh,
          onSelected: (value) => controller.player.setSpeed(value),
          itemBuilder: (context) => _speeds
              .map((s) => PopupMenuItem(
                    value: s,
                    child: Text('${s}x'),
                  ))
              .toList(),
          child: _PillButtonContent(
            icon: Icons.speed,
            label: '${speed}x',
            active: speed != 1.0,
          ),
        );
      },
    );
  }
}

class PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const PillButton(
      {super.key,
      required this.label,
      required this.icon,
      required this.active,
      required this.onTap,
      this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      onLongPress: onLongPress,
      child: _PillButtonContent(icon: icon, label: label, active: active),
    );
  }
}

class _PillButtonContent extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;

  const _PillButtonContent({
    required this.label,
    required this.icon,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? scheme.primary.withValues(alpha: 0.16)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 16,
              color: active ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
