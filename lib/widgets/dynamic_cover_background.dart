import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// Envolve [child] com um fundo em gradiente derivado das cores dominantes
/// da capa. Reage a trocas de [coverBytes] com uma transição suave; sem
/// capa, cai num gradiente neutro baseado no ColorScheme do tema atual.
///
/// Uso típico: envolver a tela de player ou o editor de metadados pra dar
/// aquele efeito de "ambiente" que segue a cor da capa.
class DynamicCoverBackground extends StatefulWidget {
  final Uint8List? coverBytes;
  final Widget child;
  final Duration transitionDuration;

  const DynamicCoverBackground({
    super.key,
    required this.coverBytes,
    required this.child,
    this.transitionDuration = const Duration(milliseconds: 500),
  });

  @override
  State<DynamicCoverBackground> createState() => _DynamicCoverBackgroundState();
}

class _DynamicCoverBackgroundState extends State<DynamicCoverBackground> {
  Color? _top;
  Color? _bottom;
  Uint8List? _lastProcessed;

  @override
  void initState() {
    super.initState();
    _generatePalette();
  }

  @override
  void didUpdateWidget(covariant DynamicCoverBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.coverBytes != oldWidget.coverBytes) {
      _generatePalette();
    }
  }

  Future<void> _generatePalette() async {
    final bytes = widget.coverBytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        setState(() {
          _top = null;
          _bottom = null;
          _lastProcessed = null;
        });
      }
      return;
    }
    if (bytes == _lastProcessed) return;

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        maximumColorCount: 12,
      );
      if (!mounted) return;
      setState(() {
        _top = palette.dominantColor?.color ?? palette.vibrantColor?.color;
        _bottom = palette.darkMutedColor?.color ?? palette.mutedColor?.color;
        _lastProcessed = bytes;
      });
    } catch (_) {
      // Imagem corrompida ou não suportada — mantém o gradiente neutro em
      // vez de derrubar a tela.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = _top ?? scheme.surfaceContainerHigh;
    final bottom = _bottom ?? scheme.surface;

    return AnimatedContainer(
      duration: widget.transitionDuration,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.55, 1.0],
          colors: [
            top.withValues(alpha: 0.55),
            bottom.withValues(alpha: 0.85),
            scheme.surface,
          ],
        ),
      ),
      child: widget.child,
    );
  }
}
