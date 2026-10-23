import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/platform_style.dart';

/// Shows [builder]'s content the way the platform presents a modal task:
/// a bottom sheet on iOS, Android and phone-sized web, a centred dialog on
/// Windows and desktop web, where sheets rising from the bottom edge of a
/// large window read as foreign. Takes the same arguments as
/// [showModalBottomSheet], so call sites swap one for the other; the
/// content pops with a result exactly as it would from a sheet.
///
/// [shape] is ignored on purpose: the corner radius is the platform's (28
/// on Android, 16 on iOS and the web, the dialog radius on desktop).
///
/// Content that draws its own [SheetGrabber] leaves [grabber] off; for
/// content that doesn't, [grabber] adds one above it.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool grabber = false,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  AnimationStyle? sheetAnimationStyle,
  Color? backgroundColor,
  ShapeBorder? shape,
  BoxConstraints? constraints,
}) {
  final bg = backgroundColor ?? AppColors.card;
  final asDialog = PlatformStyle.isDesktopLike &&
      MediaQuery.sizeOf(context).width >= Breakpoints.compact;

  if (asDialog) {
    final size = MediaQuery.sizeOf(context);
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) => Dialog(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PlatformStyle.dialogRadius),
          side: BorderSide(color: AppColors.border),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constraints?.maxWidth.isFinite == true
                ? constraints!.maxWidth
                : 560,
            maxHeight: size.height * 0.85,
          ),
          // Bounded like a sheet, so content that sizes a Flexible list
          // to the space left keeps working.
          child: _DialogScope(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _withGrabber(grabber, builder(dialogContext)),
            ),
          ),
        ),
      ),
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    builder: (sheetContext) => _withGrabber(grabber, builder(sheetContext)),
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    sheetAnimationStyle: sheetAnimationStyle ?? Motion.sheetStyle,
    backgroundColor: bg,
    constraints: constraints ?? const BoxConstraints(maxWidth: 640),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PlatformStyle.isAndroid ? 28 : 16),
      ),
    ),
  );
}

Widget _withGrabber(bool grabber, Widget child) => !grabber
    ? child
    : Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [const SheetGrabber(), Flexible(child: child)],
      );

/// Marks content shown by [showAppSheet] as a dialog rather than a sheet.
class _DialogScope extends InheritedWidget {
  const _DialogScope({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DialogScope>() != null;

  @override
  bool updateShouldNotify(_DialogScope oldWidget) => false;
}

/// The grabber at the top of a sheet (both iOS and Material sheets carry
/// one). Inside a desktop dialog nothing is dragged, so it leaves only its
/// top spacing.
class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    if (_DialogScope.of(context)) return const SizedBox(height: 16);
    final android = PlatformStyle.isAndroid;
    return Center(
      child: Container(
        width: android ? 32 : 36,
        height: android ? 4 : 5,
        margin: EdgeInsets.only(top: android ? 16 : 8, bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.text30,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}
