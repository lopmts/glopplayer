import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glopplayer/services/app_logger.dart';

/// Tela de monitoramento de logs do app.
///
/// Diferente da tela de referência (filtro em dropdown + lista simples),
/// aqui os logs aparecem como uma timeline: cada nível tem uma cor própria,
/// os filtros são chips roláveis, e cada entrada pode ser expandida para
/// ver detalhe/stack trace e copiada individualmente.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  LogLevel? _selectedLevel; // null = todos
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    AppLogger.instance.addListener(_onLogsChanged);
    _searchController.addListener(() {
      setState(() => _query = _searchController.text);
    });
  }

  @override
  void dispose() {
    AppLogger.instance.removeListener(_onLogsChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onLogsChanged() => setState(() {});

  Color _colorForLevel(LogLevel level, ColorScheme scheme) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return scheme.primary;
      case LogLevel.warning:
        return Colors.amber;
      case LogLevel.error:
        return scheme.error;
    }
  }

  IconData _iconForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Icons.bug_report_outlined;
      case LogLevel.info:
        return Icons.info_outline;
      case LogLevel.warning:
        return Icons.warning_amber_rounded;
      case LogLevel.error:
        return Icons.error_outline;
    }
  }

  void _copyToClipboard(String text, {String? feedback}) {
    Clipboard.setData(ClipboardData(text: text));
    if (feedback != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(feedback), duration: const Duration(seconds: 1)),
      );
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar logs'),
        content: const Text(
            'Isso apaga todas as entradas de log em memória. Deseja continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      AppLogger.instance.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries =
        AppLogger.instance.filtered(level: _selectedLevel, query: _query);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            tooltip: 'Copiar todos',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: entries.isEmpty
                ? null
                : () => _copyToClipboard(
                      AppLogger.instance.exportAsText(),
                      feedback: 'Logs copiados para a área de transferência',
                    ),
          ),
          IconButton(
            tooltip: 'Limpar logs',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed:
                AppLogger.instance.entries.isEmpty ? null : _confirmClear,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(scheme),
          Expanded(
            child: entries.isEmpty
                ? _buildEmptyState(scheme)
                : _buildTimeline(entries, scheme),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar por mensagem ou tag...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => _searchController.clear(),
                    ),
              isDense: true,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _levelChip(null, 'Todos', scheme),
                const SizedBox(width: 8),
                for (final level in LogLevel.values) ...[
                  _levelChip(level, level.label, scheme),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelChip(LogLevel? level, String label, ColorScheme scheme) {
    final selected = _selectedLevel == level;
    final color =
        level == null ? scheme.primary : _colorForLevel(level, scheme);
    final count = level == null
        ? AppLogger.instance.entries.length
        : AppLogger.instance.entries.where((e) => e.level == level).length;

    return ChoiceChip(
      label: Text('$label${count > 0 ? ' ($count)' : ''}'),
      selected: selected,
      onSelected: (_) => setState(() => _selectedLevel = level),
      avatar: level == null
          ? null
          : Icon(_iconForLevel(level),
              size: 16, color: selected ? null : color),
      selectedColor: color.withValues(alpha: 0.22),
      side: BorderSide(color: selected ? color : color.withValues(alpha: 0.35)),
      labelStyle: TextStyle(
        color: selected ? color : null,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme scheme) {
    final hasFilters = _selectedLevel != null || _query.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilters
                  ? Icons.filter_alt_off_outlined
                  : Icons.receipt_long_outlined,
              size: 56,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              hasFilters
                  ? 'Nenhum log corresponde ao filtro'
                  : 'Nenhum log ainda',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              hasFilters
                  ? 'Tente limpar a busca ou trocar o nível selecionado'
                  : 'Os logs do app vão aparecer aqui conforme você usa o app',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(List<LogEntry> entries, ColorScheme scheme) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final color = _colorForLevel(entry.level, scheme);
        final isLast = index == entries.length - 1;
        final expanded = _expanded.contains(index);
        final hasDetail = entry.detail != null && entry.detail!.isNotEmpty;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Trilho da timeline
              Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        color: scheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Conteúdo
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: GestureDetector(
                    onTap: hasDetail
                        ? () => setState(() {
                              expanded
                                  ? _expanded.remove(index)
                                  : _expanded.add(index);
                            })
                        : null,
                    onLongPress: () => _copyToClipboard(
                      entry.toPlainText(),
                      feedback: 'Entrada copiada',
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border(left: BorderSide(color: color, width: 3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(_iconForLevel(entry.level),
                                  size: 14, color: color),
                              const SizedBox(width: 6),
                              Text(
                                entry.tag,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const Spacer(),
                              Text(
                                _formatTime(entry.timestamp),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.message,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (hasDetail) ...[
                            const SizedBox(height: 6),
                            AnimatedCrossFade(
                              firstChild: const SizedBox.shrink(),
                              secondChild: Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  entry.detail!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontFamily: 'monospace',
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                              crossFadeState: expanded
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              duration: const Duration(milliseconds: 150),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                expanded
                                    ? 'toque para recolher'
                                    : 'toque para detalhes',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant
                                          .withValues(alpha: 0.7),
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
