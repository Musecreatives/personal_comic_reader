import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Wraps the app with a slim "you're offline" banner and flushes the
/// queued progress updates as soon as connectivity comes back - web
/// reports connectivity via `navigator.onLine` through the same package,
/// so this works there too, not just native.
class ConnectivityBanner extends ConsumerStatefulWidget {
  final Widget child;
  const ConnectivityBanner({super.key, required this.child});

  @override
  ConsumerState<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends ConsumerState<ConnectivityBanner> {
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then(_handle);
    Connectivity().onConnectivityChanged.listen(_handle);
  }

  void _handle(List<ConnectivityResult> results) {
    final nowOffline = results.every((r) => r == ConnectivityResult.none);
    final wasOffline = _offline;
    if (mounted) setState(() => _offline = nowOffline);

    if (wasOffline && !nowOffline) {
      final backend = ref.read(activeBackendProvider).valueOrNull;
      if (backend != null) {
        ref.read(progressSyncProvider).flushQueue(backend);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_offline)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Offline - showing downloaded content',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}

@visibleForTesting
bool isFullyOffline(List<ConnectivityResult> results) =>
    results.every((r) => r == ConnectivityResult.none);
