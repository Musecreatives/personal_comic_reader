import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

class DayStat {
  final DateTime date;
  final int pages;
  final int seconds;

  const DayStat({required this.date, this.pages = 0, this.seconds = 0});

  DayStat copyWith({int? pages, int? seconds}) => DayStat(
        date: date,
        pages: pages ?? this.pages,
        seconds: seconds ?? this.seconds,
      );
}

/// Local-only reading activity: pages read and active reading time, per
/// day. Never sent to any server - purely for the Stats screen. Can be
/// disabled entirely, in which case every record call is a no-op and
/// nothing is written.
class ReadingStatsStore {
  static const _boxName = 'reading_stats';
  static const _enabledKey = '_enabled';

  late final Box<String> _box;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  bool get enabled => _box.get(_enabledKey) != 'false';

  Future<void> setEnabled(bool value) => _box.put(_enabledKey, '$value');

  String _keyFor(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DayStat _read(DateTime date) {
    final raw = _box.get(_keyFor(date));
    if (raw == null) return DayStat(date: date);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return DayStat(
      date: date,
      pages: json['pages'] as int? ?? 0,
      seconds: json['seconds'] as int? ?? 0,
    );
  }

  Future<void> _write(DayStat stat) => _box.put(
        _keyFor(stat.date),
        jsonEncode({'pages': stat.pages, 'seconds': stat.seconds}),
      );

  Future<void> recordPages(int count, {DateTime? date}) async {
    if (!enabled || count <= 0) return;
    final today = date ?? DateTime.now();
    final current = _read(today);
    await _write(current.copyWith(pages: current.pages + count));
  }

  Future<void> recordSeconds(int seconds, {DateTime? date}) async {
    if (!enabled || seconds <= 0) return;
    final today = date ?? DateTime.now();
    final current = _read(today);
    await _write(current.copyWith(seconds: current.seconds + seconds));
  }

  /// The last [n] days including today, oldest first - ready to feed
  /// straight into a bar chart.
  List<DayStat> lastDays(int n) {
    final now = DateTime.now();
    return List.generate(n, (i) => _read(now.subtract(Duration(days: n - 1 - i))));
  }

  int get totalPages {
    var total = 0;
    for (final key in _box.keys) {
      if (key == _enabledKey) continue;
      final raw = _box.get(key as String);
      if (raw == null) continue;
      total += (jsonDecode(raw) as Map<String, dynamic>)['pages'] as int? ?? 0;
    }
    return total;
  }

  int get totalSeconds {
    var total = 0;
    for (final key in _box.keys) {
      if (key == _enabledKey) continue;
      final raw = _box.get(key as String);
      if (raw == null) continue;
      total += (jsonDecode(raw) as Map<String, dynamic>)['seconds'] as int? ?? 0;
    }
    return total;
  }

  /// Consecutive days with at least one page read, counting backward from
  /// today. Today doesn't break the streak just for not having activity
  /// *yet* - only a full missed day does.
  int get currentStreak {
    var streak = 0;
    var day = DateTime.now();
    var first = true;
    while (true) {
      final stat = _read(day);
      if (stat.pages == 0) {
        if (first) {
          first = false;
          day = day.subtract(const Duration(days: 1));
          continue;
        }
        break;
      }
      streak++;
      first = false;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }
}
