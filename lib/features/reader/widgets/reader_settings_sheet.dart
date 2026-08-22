import 'package:flutter/material.dart';

import '../../../core/reader/color_filters.dart';
import '../../../core/reader/reader_settings.dart';

/// Slide-up settings sheet, Panels-style: grouped segmented controls and
/// sliders, no navigation of its own - every change calls [onChanged]
/// immediately so the reader behind it updates live.
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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Reader settings',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              _SectionLabel('Mode'),
              SegmentedButton<ReaderMode>(
                segments: const [
                  ButtonSegment(
                      value: ReaderMode.single,
                      icon: Icon(Icons.crop_portrait),
                      label: Text('Single')),
                  ButtonSegment(
                      value: ReaderMode.double,
                      icon: Icon(Icons.menu_book),
                      label: Text('Double')),
                  ButtonSegment(
                      value: ReaderMode.verticalContinuous,
                      icon: Icon(Icons.view_agenda),
                      label: Text('Webtoon')),
                ],
                selected: {_settings.mode},
                onSelectionChanged: (s) =>
                    _update((c) => c.copyWith(mode: s.first)),
              ),
              const SizedBox(height: 16),
              _SectionLabel('Direction'),
              SegmentedButton<ReadingDirection>(
                segments: const [
                  ButtonSegment(
                      value: ReadingDirection.ltr, label: Text('LTR')),
                  ButtonSegment(
                      value: ReadingDirection.rtl, label: Text('RTL')),
                ],
                selected: {_settings.direction},
                onSelectionChanged: (s) =>
                    _update((c) => c.copyWith(direction: s.first)),
              ),
              const SizedBox(height: 16),
              _SectionLabel('Fit'),
              SegmentedButton<PageFit>(
                segments: const [
                  ButtonSegment(value: PageFit.width, label: Text('Width')),
                  ButtonSegment(value: PageFit.height, label: Text('Height')),
                  ButtonSegment(value: PageFit.screen, label: Text('Screen')),
                  ButtonSegment(
                      value: PageFit.original, label: Text('Original')),
                ],
                selected: {_settings.fit},
                onSelectionChanged: (s) =>
                    _update((c) => c.copyWith(fit: s.first)),
              ),
              if (_settings.mode == ReaderMode.double) ...[
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cover alone'),
                  value: _settings.doublePageCoverAlone,
                  onChanged: (v) =>
                      _update((c) => c.copyWith(doublePageCoverAlone: v)),
                ),
                _SectionLabel('Page offset'),
                Slider(
                  value: _settings.doublePageOffset.toDouble(),
                  min: 0,
                  max: 3,
                  divisions: 3,
                  label: '${_settings.doublePageOffset}',
                  onChanged: (v) => _update(
                      (c) => c.copyWith(doublePageOffset: v.round())),
                ),
              ],
              if (_settings.mode == ReaderMode.verticalContinuous) ...[
                _SectionLabel('Page gap'),
                Slider(
                  value: _settings.pageGap,
                  min: 0,
                  max: 32,
                  onChanged: (v) => _update((c) => c.copyWith(pageGap: v)),
                ),
              ],
              const SizedBox(height: 8),
              _SectionLabel('Brightness'),
              Slider(
                value: _settings.brightness.toDouble(),
                min: 20,
                max: 100,
                onChanged: (v) =>
                    _update((c) => c.copyWith(brightness: v.round())),
              ),
              _SectionLabel('Filter'),
              SegmentedButton<String>(
                segments: readerColorFilterNames
                    .map((n) => ButtonSegment(value: n, label: Text(n)))
                    .toList(),
                selected: {_settings.colorFilter},
                onSelectionChanged: (s) =>
                    _update((c) => c.copyWith(colorFilter: s.first)),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tap zones'),
                value: _settings.tapZonesEnabled,
                onChanged: (v) =>
                    _update((c) => c.copyWith(tapZonesEnabled: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep screen on'),
                value: _settings.keepScreenOn,
                onChanged: (v) =>
                    _update((c) => c.copyWith(keepScreenOn: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Upscale (sharper zoom)'),
                value: _settings.upscale,
                onChanged: (v) => _update((c) => c.copyWith(upscale: v)),
              ),
              const Divider(height: 32),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remember for this series'),
                subtitle: const Text(
                    'Save these settings for this series instead of using the app default'),
                value: _remember,
                onChanged: (v) {
                  setState(() => _remember = v);
                  widget.onRememberChanged(v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
