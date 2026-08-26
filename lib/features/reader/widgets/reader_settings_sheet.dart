import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../../../core/reader/color_filters.dart';
import '../../../core/reader/reader_settings.dart';

/// Reader settings sheet per the 5a design: a glass bottom sheet with
/// grouped cards, mono section labels, and accent "VALUE ▾" pickers.
/// Every change calls [onChanged] immediately so the reader behind it
/// updates live.
class ReaderSettingsSheet extends StatefulWidget {
  final ReaderSettings settings;
  final bool rememberForSeries;
  final ValueChanged<ReaderSettings> onChanged;
  final ValueChanged<bool> onRememberChanged;

  const ReaderSettingsSheet({
    super.key,
    required this.settings,
    required this.rememberForSeries,
    required this.onChanged,
    required this.onRememberChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required ReaderSettings settings,
    required bool rememberForSeries,
    required ValueChanged<ReaderSettings> onChanged,
    required ValueChanged<bool> onRememberChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReaderSettingsSheet(
        settings: settings,
        rememberForSeries: rememberForSeries,
        onChanged: onChanged,
        onRememberChanged: onRememberChanged,
      ),
    );
  }

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late ReaderSettings _settings;
  late bool _remember;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _remember = widget.rememberForSeries;
  }

  void _update(ReaderSettings Function(ReaderSettings) f) {
    setState(() => _settings = f(_settings));
    widget.onChanged(_settings);
  }

  Future<T?> _showPicker<T>(BuildContext context, String title, List<(T, String)> options) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Text(title, style: AppText.body(size: 15, weight: FontWeight.w600)),
            ),
            for (final (value, label) in options)
              ListTile(
                title: Text(label, style: AppText.body(size: 14)),
                onTap: () => Navigator.of(context).pop(value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.canvas.withValues(alpha: 0.97),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.track,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Reader settings', style: AppText.body(size: 19, weight: FontWeight.w600)),
                ),
                const SizedBox(height: 16),
                _GroupLabel('LAYOUT'),
                _Group(children: [
                  _ValueRow(
                    label: 'Reading direction',
                    value: _settings.direction == ReadingDirection.ltr ? 'LEFT → RIGHT' : 'RIGHT → LEFT',
                    onTap: () async {
                      final v = await _showPicker(context, 'Reading direction', const [
                        (ReadingDirection.ltr, 'Left → right'),
                        (ReadingDirection.rtl, 'Right → left'),
                      ]);
                      if (v != null) _update((c) => c.copyWith(direction: v));
                    },
                  ),
                  _ValueRow(
                    label: 'Page fit',
                    value: _fitLabel(_settings.fit),
                    onTap: () async {
                      final v = await _showPicker(context, 'Page fit', const [
                        (PageFit.width, 'Fit width'),
                        (PageFit.height, 'Fit height'),
                        (PageFit.screen, 'Fit screen'),
                        (PageFit.original, 'Original size'),
                      ]);
                      if (v != null) _update((c) => c.copyWith(fit: v));
                    },
                  ),
                  _ValueRow(
                    label: 'Reader mode',
                    value: _modeLabel(_settings.mode),
                    isLast: !(_settings.mode == ReaderMode.double ||
                        _settings.mode == ReaderMode.verticalContinuous),
                    onTap: () async {
                      final v = await _showPicker(context, 'Reader mode', const [
                        (ReaderMode.single, 'Paged'),
                        (ReaderMode.verticalContinuous, 'Webtoon'),
                        (ReaderMode.double, 'Double'),
                      ]);
                      if (v != null) _update((c) => c.copyWith(mode: v));
                    },
                  ),
                  if (_settings.mode == ReaderMode.double)
                    _ToggleRow(
                      title: 'Cover alone',
                      subtitle: 'First page is a single cover, not paired',
                      value: _settings.doublePageCoverAlone,
                      isLast: true,
                      onChanged: (v) => _update((c) => c.copyWith(doublePageCoverAlone: v)),
                    ),
                ]),
                if (_settings.mode == ReaderMode.verticalContinuous) ...[
                  _GroupLabel('WEBTOON'),
                  _Group(children: [
                    _SliderRow(
                      label: 'Page gap',
                      value: _settings.pageGap,
                      min: 0,
                      max: 32,
                      display: '${_settings.pageGap.round()} PX',
                      isLast: true,
                      onChanged: (v) => _update((c) => c.copyWith(pageGap: v)),
                    ),
                  ]),
                ],
                _GroupLabel('GESTURES & CHROME'),
                _Group(children: [
                  _ToggleRow(
                    title: 'Tap zones',
                    subtitle: 'Tap the left/right edge to turn pages',
                    value: _settings.tapZonesEnabled,
                    onChanged: (v) => _update((c) => c.copyWith(tapZonesEnabled: v)),
                  ),
                  _ToggleRow(
                    title: 'Keep screen on',
                    subtitle: 'Prevent sleep while reading',
                    value: _settings.keepScreenOn,
                    onChanged: (v) => _update((c) => c.copyWith(keepScreenOn: v)),
                  ),
                  _ToggleRow(
                    title: 'Upscale',
                    subtitle: 'Sharper zoom on low-resolution pages',
                    value: _settings.upscale,
                    isLast: true,
                    onChanged: (v) => _update((c) => c.copyWith(upscale: v)),
                  ),
                ]),
                _GroupLabel('DISPLAY'),
                _Group(children: [
                  _SliderRow(
                    label: 'Brightness',
                    value: _settings.brightness.toDouble(),
                    min: 20,
                    max: 100,
                    display: '${_settings.brightness}%',
                    onChanged: (v) => _update((c) => c.copyWith(brightness: v.round())),
                  ),
                  _ValueRow(
                    label: 'Color filter',
                    value: _settings.colorFilter.toUpperCase(),
                    isLast: true,
                    onTap: () async {
                      final v = await _showPicker(
                        context,
                        'Color filter',
                        readerColorFilterNames.map((n) => (n, n)).toList(),
                      );
                      if (v != null) _update((c) => c.copyWith(colorFilter: v));
                    },
                  ),
                ]),
                _GroupLabel('SCOPE'),
                _Group(children: [
                  _ToggleRow(
                    title: 'Remember for this series',
                    subtitle: 'Otherwise these settings apply app-wide',
                    value: _remember,
                    isLast: true,
                    onChanged: (v) {
                      setState(() => _remember = v);
                      widget.onRememberChanged(v);
                    },
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
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

  String _fitLabel(PageFit fit) {
    switch (fit) {
      case PageFit.width:
        return 'FIT WIDTH';
      case PageFit.height:
        return 'FIT HEIGHT';
      case PageFit.screen:
        return 'FIT SCREEN';
      case PageFit.original:
        return 'ORIGINAL';
    }
  }
}

class _GroupLabel extends StatelessWidget {
  final String label;
  const _GroupLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Text(label, style: AppText.sectionLabel()),
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool isLast;
  const _ValueRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppText.body(size: 14)),
            Text('$value ▾', style: AppText.mono(size: 12, color: AppColors.accentLink)),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isLast;
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.body(size: 14)),
                const SizedBox(height: 4),
                Text(subtitle, style: AppText.body(size: 11, color: AppColors.text45)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;
  final bool isLast;
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 4),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: AppText.body(size: 14)),
              Text(display, style: AppText.mono(size: 12, color: AppColors.accentLink)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.track,
              thumbColor: Colors.white,
              overlayColor: AppColors.accent.withValues(alpha: 0.15),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
