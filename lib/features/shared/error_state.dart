import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// Consistent "something went wrong" state used across screens: a short,
/// human-readable cause plus a retry action. Raw exception text goes in the
/// expandable detail, not the headline - nobody wants to read a stack trace
/// to know what to do next.
class AppErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const AppErrorState({super.key, required this.error, this.onRetry});

  String get _headline {
    final msg = error.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('connection refused') ||
        msg.contains('failed host lookup')) {
      return "Can't reach the server";
    }
    if (msg.contains('401') || msg.contains('unauthorized')) {
      return 'Sign-in failed';
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return 'The server took too long to respond';
    }
    if (msg.contains('certificate') || msg.contains('handshake')) {
      return 'TLS certificate problem';
    }
    return 'Something went wrong';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: AppColors.dangerText),
            const SizedBox(height: 14),
            Text(_headline,
                textAlign: TextAlign.center,
                style: AppText.body(size: 15, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('$error',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 11.5, color: AppColors.text45)),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonal(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.fillSubtle,
                  foregroundColor: AppColors.text,
                ),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
