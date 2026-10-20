import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Keeps this device current with the others while it is open: syncs when the
/// app comes back to the foreground and every couple of minutes after, so a
/// desktop left running picks up what was read on the phone. [startSync]
/// throttles, so a burst of resumes costs one round trip.
class SyncScheduler extends ConsumerStatefulWidget {
  final Widget child;
  const SyncScheduler({super.key, required this.child});

  @override
  ConsumerState<SyncScheduler> createState() => _SyncSchedulerState();
}

class _SyncSchedulerState extends ConsumerState<SyncScheduler>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _sync());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  void _sync() {
    if (ref.read(currentUsernameProvider) == null) return;
    startSync(ProviderScope.containerOf(context), force: false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
