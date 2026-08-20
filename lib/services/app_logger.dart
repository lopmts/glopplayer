import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Níveis de severidade de log, do menos ao mais crítico.
enum LogLevel { debug, info, warning, error }

extension LogLevelX on LogLevel {
  String get label {
    switch (this) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }
}

/// Uma única entrada de log.
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? detail; // stack trace, payload, etc.

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.detail,
  });

  String toPlainText() {
    final ts = timestamp.toIso8601String();
    final base = '[$ts] ${level.label} [$tag] $message';
    return detail == null || detail!.isEmpty ? base : '$base\n$detail';
  }
}

/// Logger global do app: acumula entradas em memória (buffer circular),
/// notifica ouvintes (ChangeNotifier) e oferece filtro/busca/export.
///
/// Uso em qualquer lugar do app:
///   AppLogger.instance.i('Player', 'Faixa iniciada: $title');
///   AppLogger.instance.e('Sync', 'Falha ao sincronizar', detail: e.toString());
class AppLogger extends ChangeNotifier {
  AppLogger._internal();
  static final AppLogger instance = AppLogger._internal();

  static const int _maxEntries = 500;

  final ListQueue<LogEntry> _entries = ListQueue<LogEntry>();

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void log(
    LogLevel level,
    String tag,
    String message, {
    String? detail,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      detail: detail,
    );

    _entries.addFirst(entry); // mais recente primeiro
    while (_entries.length > _maxEntries) {
      _entries.removeLast();
    }

    if (kDebugMode) {
      // eco no console durante desenvolvimento
      // ignore: avoid_print
      print(entry.toPlainText());
    }

    notifyListeners();
  }

  void d(String tag, String message, {String? detail}) =>
      log(LogLevel.debug, tag, message, detail: detail);

  void i(String tag, String message, {String? detail}) =>
      log(LogLevel.info, tag, message, detail: detail);

  void w(String tag, String message, {String? detail}) =>
      log(LogLevel.warning, tag, message, detail: detail);

  void e(String tag, String message, {String? detail}) =>
      log(LogLevel.error, tag, message, detail: detail);

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  List<LogEntry> filtered({LogLevel? level, String query = ''}) {
    final q = query.trim().toLowerCase();
    return _entries.where((entry) {
      final matchesLevel = level == null || entry.level == level;
      final matchesQuery = q.isEmpty ||
          entry.message.toLowerCase().contains(q) ||
          entry.tag.toLowerCase().contains(q);
      return matchesLevel && matchesQuery;
    }).toList();
  }

  String exportAsText() {
    return _entries.map((e) => e.toPlainText()).join('\n\n');
  }
}
