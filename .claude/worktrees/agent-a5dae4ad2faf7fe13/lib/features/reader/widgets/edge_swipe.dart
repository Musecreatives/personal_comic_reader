import 'package:flutter/widgets.dart';

/// Fires [onPastStart] once per drag when the user keeps dragging back past
/// the first page/top of the reader - the touch equivalent of tapping "back"
/// on page 1 - by counting overscroll. RTL needs no special case: the
/// PageView already flips its axis, so "before the first page" is always a
/// negative overscroll. Only clamping physics report overscroll this way
/// (Android/desktop/web); iOS-style bounce won't trigger it.
class EdgeSwipe extends StatefulWidget {
  final VoidCallback onPastStart;
  final Widget child;
  const EdgeSwipe({super.key, required this.onPastStart, required this.child});

  @override
  State<EdgeSwipe> createState() => _EdgeSwipeState();
}

class _EdgeSwipeState extends State<EdgeSwipe> {
  static const _threshold = 40.0;
  double _pulled = 0;
  bool _fired = false;

  bool _onNotification(ScrollNotification n) {
    if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < 0) {
      _pulled -= n.overscroll;
      if (!_fired && _pulled > _threshold) {
        _fired = true;
        widget.onPastStart();
      }
    } else if (n is ScrollEndNotification) {
      _pulled = 0;
      _fired = false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: widget.child,
      );
}
