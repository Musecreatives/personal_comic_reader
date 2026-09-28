import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';

extension PopOrHome on BuildContext {
  /// Leaves the current screen. The app reopens on whatever screen was last
  /// open, so that screen can be the only one in the stack - a plain pop()
  /// then does nothing. In that case go where it's normally reached from.
  void popOrHome({String? fallback}) {
    if (canPop()) {
      pop();
      return;
    }
    final path = GoRouterState.of(this).uri.path;
    final fromSettings = path.startsWith('/settings') ||
        const ['/local-library', '/collections', '/stats'].contains(path);
    go(fallback ?? (fromSettings ? '/settings' : '/home'));
  }
}

/// The circular glass back button used throughout the design package.
/// Defaults to [PopOrHome.popOrHome]; pass [onTap] to override.
class AppBackButton extends StatelessWidget {
  final VoidCallback? onTap;
  const AppBackButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.fillSubtle,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap ?? () => context.popOrHome(),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: AppColors.text),
        ),
      ),
    );
  }
}

/// A screen header: back button + large title, the pattern every pushed
/// settings-style screen in the app uses.
class AppScreenHeader extends StatelessWidget {
  final String title;
  final double titleSize;
  final Widget? trailing;
  final VoidCallback? onBack;

  const AppScreenHeader({
    super.key,
    required this.title,
    this.titleSize = 24,
    this.trailing,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: Row(
        children: [
          AppBackButton(onTap: onBack),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.largeTitle(size: titleSize)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
