import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LogLevel { info, warning, error }

class LogEntry {
  final DateTime at;
  final LogLevel level;
  final String message;
  final String? stack;
  LogEntry(this.level, this.message, {this.stack}) : at = DateTime.now();

  Map<String, dynamic> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'level': level.name,
        'message': message,
        'stack': ?stack,
      };
}

/// One HTTP call, filled in as it completes.
class NetworkEntry {
  final DateTime at = DateTime.now();
  final String method;
  final Uri uri;
  final String? requestBody;
  int? status;
  Duration? duration;
  String? error;
  int? bytes;
  String? responseBody;

  NetworkEntry(this.method, this.uri, this.requestBody);

  bool get pending => status == null && error == null;
  bool get failed => error != null || (status ?? 0) >= 400;

  Map<String, dynamic> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'method': method,
        'url': '$uri',
        'status': ?status,
        'ms': ?duration?.inMilliseconds,
        'error': ?error,
        'bytes': ?bytes,
        'request': ?requestBody,
        'response': ?responseBody,
      };
}

/// In-app logs and network activity (the Pulse idea): kept in memory, shown
/// on the Diagnostics screen and attached to problem reports.
class DebugLog extends ChangeNotifier {
  DebugLog._();
  static final instance = DebugLog._();

  static const _max = 400;
  static const _previewChars = 2000;
  static const _debugModeKey = 'debug_mode';

  final logs = ListQueue<LogEntry>();
  final network = ListQueue<NetworkEntry>();

  /// Debug mode shows a floating button over every screen.
  final debugMode = ValueNotifier(false);

  bool _notifyQueued = false;

  /// Hooks Flutter/platform errors and debugPrint, and restores debug mode.
  Future<void> install() async {
    final flutterError = FlutterError.onError;
    FlutterError.onError = (d) {
      log(d.exceptionAsString(), level: LogLevel.error, stack: d.stack);
      flutterError?.call(d);
    };
    final platformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (e, s) {
      log('$e', level: LogLevel.error, stack: s);
      return platformError?.call(e, s) ?? false;
    };
    final print = debugPrint;
    debugPrint = (m, {wrapWidth}) {
      if (m != null) log(m);
      print(m, wrapWidth: wrapWidth);
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      debugMode.value = prefs.getBool(_debugModeKey) ?? false;
    } catch (_) {}
  }

  Future<void> setDebugMode(bool on) async {
    debugMode.value = on;
    try {
      await (await SharedPreferences.getInstance()).setBool(_debugModeKey, on);
    } catch (_) {}
  }

  void log(String message, {LogLevel level = LogLevel.info, Object? stack}) {
    logs.addLast(LogEntry(level, message, stack: stack?.toString()));
    while (logs.length > _max) {
      logs.removeFirst();
    }
    _changed();
  }

  int get errorCount =>
      logs.where((e) => e.level == LogLevel.error).length +
      network.where((e) => e.failed).length;

  void clear() {
    logs.clear();
    network.clear();
    _changed();
  }

  // Entries can be added mid-build (a debugPrint inside build); notifying
  // listeners right then would setState during build.
  void _changed() {
    if (_notifyQueued) return;
    _notifyQueued = true;
    Timer.run(() {
      _notifyQueued = false;
      notifyListeners();
    });
  }

  static String? _preview(Object? data) {
    if (data == null) return null;
    String text;
    if (data is String) {
      text = data;
    } else if (data is Map || data is List<Object?> && data is! List<int>) {
      try {
        text = jsonEncode(data);
      } catch (_) {
        return null;
      }
    } else {
      return null; // bytes, streams, form data
    }
    return text.length > _previewChars ? '${text.substring(0, _previewChars)}…' : text;
  }

  late final interceptor = InterceptorsWrapper(
    onRequest: (options, handler) {
      // Added before any auth interceptor, so the URL has no api_key yet.
      // Sign-in bodies carry passwords.
      final private = options.path.contains('/auth/');
      final e = NetworkEntry(options.method, options.uri,
          private ? null : _preview(options.data));
      options.extra['debugEntry'] = e;
      network.addLast(e);
      while (network.length > _max) {
        network.removeFirst();
      }
      _changed();
      handler.next(options);
    },
    onResponse: (res, handler) {
      final e = res.requestOptions.extra['debugEntry'];
      if (e is NetworkEntry) {
        e.status = res.statusCode;
        e.duration = DateTime.now().difference(e.at);
        final data = res.data;
        if (data is List<int>) e.bytes = data.length;
        if (!res.requestOptions.path.contains('/auth/')) {
          e.responseBody = _preview(data);
        }
        _changed();
      }
      handler.next(res);
    },
    onError: (err, handler) {
      final e = err.requestOptions.extra['debugEntry'];
      if (e is NetworkEntry) {
        e.status = err.response?.statusCode;
        e.duration = DateTime.now().difference(e.at);
        e.error = err.message ?? err.type.name;
        e.responseBody = _preview(err.response?.data);
        _changed();
      }
      handler.next(err);
    },
  );
}

/// A Dio whose calls show up on the Diagnostics screen.
Dio trackedDio(BaseOptions options) =>
    Dio(options)..interceptors.add(DebugLog.instance.interceptor);
