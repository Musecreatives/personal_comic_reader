import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../../../core/reader/reader_settings.dart';
import '../../../core/reader/spread_logic.dart';

/// Reader chrome per the 4b design: a translucent top bar (back, title +
/// mode label, menu) and a floating glass card at the bottom holding the
/// page slider, the Paged/Webtoon/Double mode switch, and quick actions.
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

  String _modeLabel(ReaderMode mode) {
    switch (mode) {
      case ReaderMode.single:
        return 'PAGED';
      case ReaderMode.double:
        return 'DOUBLE';
      case ReaderMode.verticalContinuous:
        return 'WEBTOON';
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopBar(
                title: title,
                subtitle: subtitle,
                modeLabel: _modeLabel(settings.mode),
                onClose: onClose,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 34,
              child: _BottomCard(
                currentPage: currentPage,
                pageCount: pageCount,
                settings: settings,
                onSeek: onSeek,
                onCycleMode: onCycleMode,
                onOpenSettings: onOpenSettings,
                onToggleDirection: onToggleDirection,
                onTogglePanelMode: onTogglePanelMode,
                modeIcon: _modeIcon,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final String modeLabel;
  final VoidCallback onClose;

  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.modeLabel,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return _Blurred(
      radius: 0,
      background: AppColors.canvas.withValues(alpha: 0.72),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Row(
            children: [
              _GlassIconButton(icon: Icons.arrow_back_ios_new_rounded, onTap: onClose),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(size: 14, weight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      subtitle.isEmpty ? modeLabel : '$subtitle · $modeLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.mono(size: 9, color: AppColors.text45),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomCard extends StatelessWidget {
  final int currentPage;
  final int pageCount;
  final ReaderSettings settings;
  final ValueChanged<int> onSeek;
  final VoidCallback onCycleMode;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleDirection;
  final VoidCallback? onTogglePanelMode;
  final IconData Function(ReaderMode) modeIcon;

  const _BottomCard({
    required this.currentPage,
    required this.pageCount,
    required this.settings,
    required this.onSeek,
    required this.onCycleMode,
    required this.onOpenSettings,
    required this.onToggleDirection,
    required this.onTogglePanelMode,
    required this.modeIcon,
  });

  @override
  Widget build(BuildContext context) {
    return _Blurred(
      radius: 22,
      background: AppColors.canvas.withValues(alpha: 0.92),
      border: Border.all(color: AppColors.borderStrong),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text('${currentPage + 1}',
                      style: AppText.mono(size: 10, color: AppColors.text45)),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: AppColors.accent,
                      inactiveTrackColor: AppColors.track,
                      thumbColor: Colors.white,
                      overlayColor: AppColors.accent.withValues(alpha: 0.15),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
                    ),
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
                ),
                SizedBox(
                  width: 26,
                  child: Text('$pageCount',
                      textAlign: TextAlign.right,
                      style: AppText.mono(size: 10, color: AppColors.text45)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ModeTab(
                    label: 'Paged',
                    active: settings.mode == ReaderMode.single,
                    onTap: () => _selectMode(ReaderMode.single),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ModeTab(
                    label: 'Webtoon',
                    active: settings.mode == ReaderMode.verticalContinuous,
                    onTap: () => _selectMode(ReaderMode.verticalContinuous),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ModeTab(
                    label: 'Double',
                    active: settings.mode == ReaderMode.double,
                    onTap: () => _selectMode(ReaderMode.double),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _QuickAction(
                    icon: settings.direction == ReadingDirection.ltr
                        ? Icons.format_textdirection_l_to_r
                        : Icons.format_textdirection_r_to_l,
                    label: 'Direction',
                    onTap: onToggleDirection,
                  ),
                  if (onTogglePanelMode != null)
                    _QuickAction(
                      icon: Icons.crop_free,
                      label: 'Panels',
                      onTap: onTogglePanelMode!,
                    ),
                  _QuickAction(
                    icon: Icons.menu_book_outlined,
                    label: 'Chapters',
                    onTap: () {},
                  ),
                  _QuickAction(
                    icon: Icons.tune,
                    label: 'Settings',
                    onTap: onOpenSettings,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectMode(ReaderMode target) {
    // ReaderMode cycles single -> double -> verticalContinuous -> single;
    // step onCycleMode until the target mode is reached (max 2 steps).
    var current = settings.mode;
    var guard = 0;
    while (current != target && guard < ReaderMode.values.length) {
      onCycleMode();
      final i = (ReaderMode.values.indexOf(current) + 1) % ReaderMode.values.length;
      current = ReaderMode.values[i];
      guard++;
    }
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ModeTab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.accent : AppColors.fillSubtle,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppText.body(
              size: 11.5,
              weight: FontWeight.w600,
              color: active ? Colors.white : AppColors.text60,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: AppColors.text60),
            const SizedBox(height: 6),
            Text(label, style: AppText.body(size: 9, weight: FontWeight.w600, color: AppColors.text60)),
          ],
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvas.withValues(alpha: 0.8),
      shape: const CircleBorder(side: BorderSide(color: Color(0xFF223349))),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 15, color: Colors.white),
        ),
      ),
    );
  }
}

class _Blurred extends StatelessWidget {
  final Widget child;
  final double radius;
  final Color background;
  final BoxBorder? border;
  const _Blurred({
    required this.child,
    required this.radius,
    required this.background,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(radius),
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}
