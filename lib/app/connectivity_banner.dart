import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design_tokens.dart';
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

  Timer? _recheck;
  StreamSubscription<List<ConnectivityResult>>? _changes;

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then(_handle);
    _changes = Connectivity().onConnectivityChanged.listen(_handle);
  }

  @override
  void dispose() {
    _recheck?.cancel();
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _handle(List<ConnectivityResult> results) async {
    var nowOffline = isFullyOffline(results);
    // iOS says "none" before it has checked the network, and while a VPN
    // like Tailscale (re)connects, though the internet works. Believe it
    // only when the server doesn't answer either.
    if (nowOffline && await _serverAnswers()) nowOffline = false;
    if (!mounted) return;
    // No change event comes when such a wrong "none" clears, so look again.
    _recheck?.cancel();
    if (nowOffline) {
      _recheck = Timer(const Duration(seconds: 15),
          () => Connectivity().checkConnectivity().then(_handle));
    }
    final wasOffline = _offline;
    // Saved series/chapter lists are served at once instead of timing out.
    ref.read(offlineSnapshotProvider).offline = nowOffline;
    ref.read(isOfflineProvider.notifier).state = nowOffline;
    setState(() => _offline = nowOffline);

    if (wasOffline && !nowOffline) {
      final backend = ref.read(activeBackendProvider).valueOrNull;
      if (backend != null) {
        ref.read(progressSyncProvider).flushQueue(backend);
      }
    }
  }

  /// Any HTTP answer from the active server, even 401, means we're online.
  Future<bool> _serverAnswers() async {
    final url = ref.read(activeServerConfigProvider)?.baseUrl ?? '';
    if (!url.startsWith('http')) return false;
    const wait = Duration(seconds: 4);
    try {
      await Dio(BaseOptions(
        connectTimeout: wait,
        receiveTimeout: wait,
        validateStatus: (_) => true,
      )).head<void>(url);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_offline) return widget.child;
    final media = MediaQuery.of(context);
    return Column(
      children: [
        _OfflineBar(topInset: media.padding.top),
        // The bar sits under the status bar, so the screen below must not
        // pad for it again.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// Amber, not red: being offline is a state, not an error (DESIGN.md).
class _OfflineBar extends StatelessWidget {
  final double topInset;
  const _OfflineBar({required this.topInset});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16, topInset + 6, 16, 7),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Semantics(
          liveRegion: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 14,
                color: AppColors.warningText,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'OFFLINE · READING DOWNLOADS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.mono(size: 10.5, color: AppColors.warningText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
bool isFullyOffline(List<ConnectivityResult> results) =>
    results.every((r) => r == ConnectivityResult.none);
