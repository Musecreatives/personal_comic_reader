import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/reader/reader_settings.dart';
import '../../../core/reader/spread_logic.dart';

/// Panels-style translucent overlay: a blurred top bar with the title and a
/// blurred bottom bar with a page slider, fading in/out over the page
/// content rather than pushing it around.
class ReaderOverlay extends StatelessWidget {
  final bool visible;
  final String title;
  final String subtitle;
  final int currentPage;
  final int pageCount;
  final ReaderSettings settings;
  final ValueChanged<int> onSeek;
  final VoidCallback onClose;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleDirection;
  final VoidCallback onCycleMode;
  final VoidCallback? onTogglePanelMode;

  const ReaderOverlay({
    super.key,
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.currentPage,
    required this.pageCount,
    required this.settings,
    required this.onSeek,
    required this.onClose,
    required this.onOpenSettings,
    required this.onToggleDirection,
    required this.onCycleMode,
    this.onTogglePanelMode,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Blurred(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: onClose,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(title,
                                style: Theme.of(context).textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis),
                            if (subtitle.isNotEmpty)
                              Text(subtitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (onTogglePanelMode != null)
                        IconButton(
                          tooltip: 'Panel view (experimental)',
                          icon: const Icon(Icons.crop_free),
                          onPressed: onTogglePanelMode,
                        ),
                      IconButton(
                        tooltip: 'Reading mode',
                        icon: Icon(_modeIcon(settings.mode)),
                        onPressed: onCycleMode,
                      ),
                      IconButton(
                        tooltip: 'Direction',
                        icon: Icon(settings.direction == ReadingDirection.ltr
                            ? Icons.format_textdirection_l_to_r
                            : Icons.format_textdirection_r_to_l),
                        onPressed: onToggleDirection,
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune),
                        onPressed: onOpenSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _Blurred(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Text('${currentPage + 1}',
                          style: Theme.of(context).textTheme.bodySmall),
                      Expanded(
                        child: Slider(
                          value: displayPositionForPage(
                                  currentPage, pageCount, settings.direction)
                              .toDouble()
                              .clamp(0, (pageCount - 1).toDouble()),
                          min: 0,
                          max: (pageCount - 1).clamp(1, 1 << 30).toDouble(),
                          onChanged: pageCount <= 1
                              ? null
                              : (v) => onSeek(pageForDisplayPosition(
                                  v.round(), pageCount, settings.direction)),
                        ),
                      ),
                      Text('$pageCount',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _modeIcon(ReaderMode mode) {
    switch (mode) {
      case ReaderMode.single:
        return Icons.crop_portrait;
      case ReaderMode.double:
        return Icons.menu_book;
      case ReaderMode.verticalContinuous:
        return Icons.view_agenda;
    }
  }
}

class _Blurred extends StatelessWidget {
  final Widget child;
  const _Blurred({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
          child: child,
        ),
      ),
    );
  }
}
