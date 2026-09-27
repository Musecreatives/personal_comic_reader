import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import '../core/backend/models.dart';
import '../core/backend/reader_backend.dart';
import 'providers.dart';

bool get _notificationsSupported =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Periodically checks every configured server's "continue reading" series
/// for a chapter count that's gone up since last check, and fires a desktop
/// notification for each one. Mobile/web just don't run this - local_notifier
/// only has Windows/macOS/Linux implementations.
class ChapterNotificationScheduler extends ConsumerStatefulWidget {
  final Widget child;
  const ChapterNotificationScheduler({super.key, required this.child});

  @override
  ConsumerState<ChapterNotificationScheduler> createState() =>
      _ChapterNotificationSchedulerState();
}

class _ChapterNotificationSchedulerState
    extends ConsumerState<ChapterNotificationScheduler> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!_notificationsSupported) return;
    // First check shortly after launch, then every 20 minutes - frequent
    // enough to be useful, infrequent enough not to hammer every server.
    Timer(const Duration(seconds: 30), _check);
    _timer = Timer.periodic(const Duration(minutes: 20), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final store = ref.read(chapterWatchStoreProvider);
    List<ReaderBackend> backends;
    try {
      backends = await ref.read(allBackendsProvider.future);
    } catch (_) {
      return;
    }
    for (final backend in backends) {
      List<Series> series;
      try {
        series = await backend.continueReading();
      } catch (_) {
        continue;
      }
      for (final s in series) {
        final key = '${backend.config.id}|${s.id}';
        final lastKnown = store.lastKnownCount(key);
        if (lastKnown != null && s.booksCount > lastKnown) {
          await LocalNotification(
            title: 'New chapter',
            body: '${s.title} - now ${s.booksCount} chapters',
          ).show();
        }
        await store.setCount(key, s.booksCount);
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Called once from main() before runApp() - required by local_notifier
/// before any notification can be shown.
Future<void> setUpChapterNotifications() async {
  if (!_notificationsSupported) return;
  await localNotifier.setup(appName: 'Shaddai Reader');
}
