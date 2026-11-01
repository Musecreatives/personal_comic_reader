import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/platform_style.dart';

/// Surface for layers that float over content: the reader chrome, the chapter
/// menu, the selection bar. Frosted glass on iOS (the platform's own look);
/// a solid card with an ink edge everywhere else, where blur over long lists
/// is costly and not the platform's idiom. Content never sits on glass.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  const GlassPanel({super.key, required this.child, required this.radius});

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    if (!PlatformStyle.isIOS) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: shape,
          border: Border.all(color: AppColors.borderStrong),
        ),
        child: ClipRRect(borderRadius: shape, child: child),
      );
    }
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.canvas.withValues(alpha: 0.7),
            borderRadius: shape,
            border: Border.all(
              color: AppColors.borderStrong.withValues(alpha: 0.8),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
