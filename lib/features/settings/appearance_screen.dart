import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/appearance/appearance_settings.dart';

/// Theme mode + accent picker (6b), with a live preview that mirrors the
/// Reading Now hero so a choice is visible before committing to it.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);

    void update(AppearanceSettings next) {
      ref.read(appearanceProvider.notifier).state = next;
      ref.read(appearanceStoreProvider).set(next);
    }

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
          children: [
            Row(
              children: [
                _BackButton(onTap: () => context.pop()),
                const SizedBox(width: 12),
                Text('Appearance', style: AppText.largeTitle(size: 24)),
              ],
            ),
            const SizedBox(height: 20),
            Text('PREVIEW', style: AppText.sectionLabel()),
            const SizedBox(height: 12),
            _LivePreview(appearance: appearance),
            const SizedBox(height: 22),
            Text('THEME', style: AppText.sectionLabel()),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final mode in AppThemeMode.values) ...[
                  Expanded(
                    child: _ThemeTile(
                      mode: mode,
                      selected: appearance.themeMode == mode,
                      onTap: () => update(appearance.copyWith(themeMode: mode)),
                    ),
                  ),
                  if (mode != AppThemeMode.values.last) const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 22),
            Text('ACCENT', style: AppText.sectionLabel()),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final option in AccentOption.values) ...[
                  _AccentSwatch(
                    option: option,
                    selected: appearance.accent == option,
                    pageColor: AppColors.page,
                    onTap: () => update(appearance.copyWith(accent: option)),
                  ),
                  if (option != AccentOption.values.last) const SizedBox(width: 11),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.fillSubtle,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: AppColors.text),
        ),
      ),
    );
  }
}

class _LivePreview extends StatelessWidget {
  final AppearanceSettings appearance;
  const _LivePreview({required this.appearance});

  @override
  Widget build(BuildContext context) {
    final accent = appearance.accent.color;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppColors.page,
          border: Border.all(color: AppColors.borderStrong),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reading Now', style: AppText.largeTitle(size: 15)),
            const SizedBox(height: 12),
            Row(
              children: [
                _PreviewCover(color: accent, showBar: true),
                const SizedBox(width: 9),
                _PreviewCover(color: AppColors.komga, showBar: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(height: 9, width: 80, decoration: BoxDecoration(color: AppColors.text.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(3))),
                      const SizedBox(height: 7),
                      Container(height: 9, width: 55, decoration: BoxDecoration(color: AppColors.text.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3))),
                      const SizedBox(height: 9),
                      Container(height: 22, width: 74, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(999))),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCover extends StatelessWidget {
  final Color color;
  final bool showBar;
  const _PreviewCover({required this.color, required this.showBar});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 82,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.5), AppColors.canvas],
        ),
      ),
      child: showBar
          ? Align(
              alignment: Alignment.bottomCenter,
              child: Container(height: 3, decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)))),
            )
          : null,
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final AppThemeMode mode;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeTile({required this.mode, required this.selected, required this.onTap});

  String get _label => switch (mode) {
        AppThemeMode.midnight => 'Midnight',
        AppThemeMode.trueBlack => 'True black',
        AppThemeMode.paper => 'Paper',
      };

  List<Color> get _preview => switch (mode) {
        AppThemeMode.midnight => [const Color(0xFF0A1420), const Color(0xFF111F31)],
        AppThemeMode.trueBlack => [Colors.black, const Color(0xFF101010)],
        AppThemeMode.paper => [const Color(0xFFF4F3F7), const Color(0xFFDDE2EA)],
      };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: selected ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _preview),
                  border: Border.all(color: AppColors.borderStrong),
                ),
              ),
              const SizedBox(height: 10),
              Text(_label,
                  style: AppText.body(
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: selected ? AppColors.text : AppColors.text60)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  final AccentOption option;
  final bool selected;
  final Color pageColor;
  final VoidCallback onTap;
  const _AccentSwatch({
    required this.option,
    required this.selected,
    required this.pageColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: option.color,
          boxShadow: selected
              ? [
                  BoxShadow(color: pageColor, blurRadius: 0, spreadRadius: 2),
                  BoxShadow(color: option.color, blurRadius: 0, spreadRadius: 4),
                ]
              : null,
        ),
      ),
    );
  }
}
