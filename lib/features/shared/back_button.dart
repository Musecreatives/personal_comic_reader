import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';

/// The circular glass back button used throughout the design package.
/// Defaults to `context.pop()`; pass [onTap] to override (e.g. a screen
/// that can also be reached as a route root with nothing to pop to).
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
        onTap: onTap ?? () => context.pop(),
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
