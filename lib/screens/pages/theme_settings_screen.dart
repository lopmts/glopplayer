import 'package:flutter/material.dart';
import 'package:glopplayer/provider/theme_provider.dart';
import 'package:provider/provider.dart';

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Tema')),
      body: ListView(
        children: [
          RadioListTile<ThemeMode>(
            title: const Text('Automático (segue o sistema)'),
            value: ThemeMode.system,
            groupValue: theme.themeMode,
            onChanged: (v) => theme.setThemeMode(v!),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Claro'),
            value: ThemeMode.light,
            groupValue: theme.themeMode,
            onChanged: (v) => theme.setThemeMode(v!),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Escuro'),
            value: ThemeMode.dark,
            groupValue: theme.themeMode,
            onChanged: (v) => theme.setThemeMode(v!),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Cor dinâmica (Material You)'),
            subtitle: const Text(
              'Usa as cores do seu papel de parede (Android 12+)',
            ),
            value: theme.useDynamicColor,
            onChanged: (v) => theme.setUseDynamicColor(v),
          ),
          SwitchListTile(
            title: const Text('AMOLED (preto puro)'),
            value: theme.useAmoled,
            onChanged: (v) => theme.setUseAmoled(v),
          ),
          SwitchListTile(
            title: const Text('Interface transparente'),
            subtitle: const Text(
              'Aplica efeito de vidro nas abas, diálogos e menus',
            ),
            value: theme.useTransparentUi,
            onChanged: theme.setUseTransparentUi,
          ),
          if (!theme.useDynamicColor) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Cor personalizada'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ColorPalettePicker(
                currentColor: theme.settings.seedColorValue,
                onColorSelected: theme.setSeedColor,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _ColorPalettePicker extends StatelessWidget {
  final int currentColor;
  final ValueChanged<Color> onColorSelected;
  const _ColorPalettePicker({
    required this.currentColor,
    required this.onColorSelected,
  });

  static const _colors = [
    Color(0xFF1DB954),
    Color(0xFF6750A4),
    Color(0xFF0061A4),
    Color(0xFF006E1C),
    Color(0xFFBA1A1A),
    Color(0xFF984061),
    Color(0xFF7D5260),
    Color(0xFF006874),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _colors.map((color) {
          final isSelected = color.toARGB32() == currentColor;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Semantics(
              button: true,
              selected: isSelected,
              label: 'Selecione cor do tema',
              child: GestureDetector(
                onTap: () => onColorSelected(color),
                child: _ColorPaletteItem(color: color, isSelected: isSelected),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ColorPaletteItem extends StatelessWidget {
  final Color color;
  final bool isSelected;

  const _ColorPaletteItem({required this.color, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: color,
      brightness: Theme.of(context).brightness,
    );
    const size = 64.0;

    return Stack(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: Container(color: scheme.primaryContainer)),
                    Expanded(child: Container(color: scheme.tertiaryContainer)),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(color: scheme.secondaryContainer),
                    ),
                    Expanded(child: Container(color: scheme.surfaceContainer)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (isSelected)
          Positioned.fill(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check, size: 16, color: scheme.primary),
              ),
            ),
          ),
      ],
    );
  }
}
