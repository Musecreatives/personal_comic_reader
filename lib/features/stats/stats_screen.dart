import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../shared/back_button.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  static const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(readingStatsStoreProvider);
    final enabled = store.enabled;
    final days = store.lastDays(7);
    final weekPages = days.fold(0, (a, d) => a + d.pages);
    final maxPages =
        days.map((d) => d.pages).fold(0, (a, b) => a > b ? a : b).clamp(1, 1 << 30);
    final avgSecondsPerPage =
        store.totalPages == 0 ? 0.0 : store.totalSeconds / store.totalPages;

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Stats', style: AppText.largeTitle())),
                  Row(
                    children: [
                      Text('TRACK', style: AppText.mono(size: 9, color: AppColors.text45)),
                      Switch(
                        value: enabled,
                        onChanged: (v) async {
                          await store.setEnabled(v);
                          setState(() {});
                        },
                        activeThumbColor: Colors.white,
                        activeTrackColor: AppColors.accent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
              child: Text('ON THIS DEVICE ONLY · NEVER SENT TO A SERVER',
                  style: AppText.mono(size: 10, color: AppColors.text42)),
            ),
            Expanded(
              child: !enabled
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Reading stats are turned off. Toggle "Track" above to '
                          'start recording pages read and time spent reading, '
                          'locally on this device only.',
                          textAlign: TextAlign.center,
                          style: AppText.body(color: AppColors.text60),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [AppColors.accent.withValues(alpha: 0.18), AppColors.card],
                            ),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: AppColors.borderStrong),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${store.currentStreak}',
                                      style: AppText.largeTitle(size: 46)),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 10, bottom: 6),
                                    child: Text('DAY\nSTREAK',
                                        style: AppText.mono(size: 10, color: AppColors.text45)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                height: 74,
                                child: BarChart(
                                  BarChartData(
                                    maxY: maxPages.toDouble() * 1.2,
                                    barTouchData: BarTouchData(enabled: true),
                                    titlesData: const FlTitlesData(show: false),
                                    borderData: FlBorderData(show: false),
                                    gridData: const FlGridData(show: false),
                                    barGroups: [
                                      for (var i = 0; i < days.length; i++)
                                        BarChartGroupData(
                                          x: i,
                                          barRods: [
                                            BarChartRodData(
                                              toY: days[i].pages.toDouble().clamp(0.001, double.infinity),
                                              color: AppColors.accent,
                                              width: 18,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 9),
                              Row(
                                children: [
                                  for (var i = 0; i < days.length; i++)
                                    Expanded(
                                      child: Text(
                                        _weekdayLabels[days[i].date.weekday - 1],
                                        textAlign: TextAlign.center,
                                        style: AppText.mono(size: 9, color: AppColors.text30),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                                child: _StatCard(value: '$weekPages', label: 'PAGES · 7D')),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _StatCard(
                                    value: _formatDuration(store.totalSeconds),
                                    label: 'READING TIME')),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _StatCard(
                                    value: avgSecondsPerPage == 0
                                        ? '—'
                                        : '${avgSecondsPerPage.toStringAsFixed(1)}s',
                                    label: 'PER PAGE')),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _StatCard(value: '${store.totalPages}', label: 'TOTAL PAGES READ', wide: true),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final bool wide;
  const _StatCard({required this.value, required this.label, this.wide = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppText.heading(size: wide ? 26 : 20)),
          const SizedBox(height: 7),
          Text(label, style: AppText.mono(size: 9)),
        ],
      ),
    );
  }
}
