import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/platform_style.dart';

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

/// The back control in the platform's own form: the circular glass
/// chevron on iOS, Material's arrow icon button on Android and the web,
/// Fluent's small square back button on Windows. Defaults to
/// [PopOrHome.popOrHome]; pass [onTap] to override.
class AppBackButton extends StatelessWidget {
  final VoidCallback? onTap;
  const AppBackButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final action = onTap ?? () => context.popOrHome();
    switch (PlatformStyle.current) {
      case UiPlatform.ios:
        return Semantics(
          button: true,
          label: 'Back',
          child: Material(
            color: AppColors.fillSubtle,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: action,
              child: SizedBox(
                width: 34,
                height: 34,
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    size: 15, color: AppColors.text),
              ),
            ),
          ),
        );
      case UiPlatform.windows:
        return Tooltip(
          message: 'Back',
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              hoverColor: AppColors.fillSubtle,
              onTap: action,
              child: SizedBox(
                width: 36,
                height: 32,
                child: Icon(Icons.arrow_back, size: 16, color: AppColors.text),
              ),
            ),
          ),
        );
      case UiPlatform.android:
      case UiPlatform.web:
        return IconButton(
          tooltip: 'Back',
          onPressed: action,
          // Pull the 48px target back to the gutter so the arrow, not its
          // padding, lines up with the page edge.
          style: IconButton.styleFrom(
              visualDensity: VisualDensity.standard),
          icon: Icon(Icons.arrow_back, color: AppColors.text),
        );
    }
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

  // Material's arrow carries its own 48px target, so the row starts
  // closer to the edge to keep the arrow on the page gutter.
  static EdgeInsets get _padding => switch (PlatformStyle.current) {
        UiPlatform.ios => const EdgeInsets.fromLTRB(20, 6, 20, 4),
        UiPlatform.windows => const EdgeInsets.fromLTRB(16, 10, 20, 6),
        UiPlatform.android ||
        UiPlatform.web =>
          const EdgeInsets.fromLTRB(8, 4, 16, 4),
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _padding,
      child: Row(
        children: [
          AppBackButton(onTap: onBack),
          SizedBox(width: PlatformStyle.isIOS ? 12 : 8),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.largeTitle(size: titleSize)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
