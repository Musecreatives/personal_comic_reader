import 'dart:convert';
import 'dart:math';

import 'package:hive_flutter/hive_flutter.dart';

import '../sync/resource_sync.dart';

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

/// Reading activity: pages read and active reading time, per day. Can be
/// disabled entirely, in which case every record call is a no-op and nothing
/// is written.
///
/// Stats add up across devices, which last-write-wins can't do. So each
/// device writes only its own record per day (`yyyy-mm-dd|<device>`), those
/// records sync like any other resource, and the numbers shown are the sum
/// over every device's records for that day.
class ReadingStatsStore {
  static const _boxName = 'reading_stats';
  static const _enabledKey = '_enabled';
  static const _deviceKey = '_device';

  late final Box<String> _box;
  late final String _device;
  final sync = ResourceSync('stats');

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    var device = _box.get(_deviceKey);
    if (device == null) {
      device = Random().nextInt(1 << 32).toRadixString(36) +
          DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      await _box.put(_deviceKey, device);
    }
    _device = device;
    await _adoptLegacyDays();
  }

  Future<bool> reconcile() => sync.reconcile(_box);

  /// Before stats synced, days were stored under a bare `yyyy-mm-dd`. Those
  /// belong to this device: move them under its key so they sync and sum.
  Future<void> _adoptLegacyDays() async {
    final legacy = _box.keys
        .cast<String>()
        .where((k) => !k.startsWith('_') && !k.contains('|'))
        .toList();
    for (final key in legacy) {
      final raw = _box.get(key);
      await _box.delete(key);
      if (raw == null) continue;
      await _box.put(
        '$key|$_device',
        jsonEncode({
          ...(jsonDecode(raw) as Map<String, dynamic>),
          '_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    }
  }

  bool get enabled => _box.get(_enabledKey) != 'false';

  Future<void> setEnabled(bool value) => _box.put(_enabledKey, '$value');

  String _keyFor(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static (int, int) _counts(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return (json['pages'] as int? ?? 0, json['seconds'] as int? ?? 0);
  }

  /// This device's own record for [date] - what a write builds on.
  DayStat _readOwn(DateTime date) {
    final raw = _box.get('${_keyFor(date)}|$_device');
    if (raw == null) return DayStat(date: date);
    final (pages, seconds) = _counts(raw);
    return DayStat(date: date, pages: pages, seconds: seconds);
  }

  /// Every device's activity for [date], summed.
  DayStat _read(DateTime date) {
    final prefix = '${_keyFor(date)}|';
    var pages = 0, seconds = 0;
    for (final key in _box.keys.cast<String>()) {
      if (!key.startsWith(prefix)) continue;
      final (p, s) = _counts(_box.get(key)!);
      pages += p;
      seconds += s;
    }
    return DayStat(date: date, pages: pages, seconds: seconds);
  }

  Future<void> _write(DayStat stat) => sync.put(
        _box,
        '${_keyFor(stat.date)}|$_device',
        {'pages': stat.pages, 'seconds': stat.seconds},
      );

  Future<void> recordPages(int count, {DateTime? date}) async {
    if (!enabled || count <= 0) return;
    final today = date ?? DateTime.now();
    final current = _readOwn(today);
    await _write(current.copyWith(pages: current.pages + count));
  }

  Future<void> recordSeconds(int seconds, {DateTime? date}) async {
    if (!enabled || seconds <= 0) return;
    final today = date ?? DateTime.now();
    final current = _readOwn(today);
    await _write(current.copyWith(seconds: current.seconds + seconds));
  }

  /// The last [n] days including today, oldest first - ready to feed
  /// straight into a bar chart.
  List<DayStat> lastDays(int n) {
    final now = DateTime.now();
    return List.generate(n, (i) => _read(now.subtract(Duration(days: n - 1 - i))));
  }

  int _total(int Function((int, int)) pick) {
    var total = 0;
    for (final key in _box.keys.cast<String>()) {
      if (key.startsWith('_')) continue;
      total += pick(_counts(_box.get(key)!));
    }
    return total;
  }

  int get totalPages => _total((c) => c.$1);

  int get totalSeconds => _total((c) => c.$2);

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
