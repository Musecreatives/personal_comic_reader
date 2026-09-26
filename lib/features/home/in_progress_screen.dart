import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../app/providers.dart';
import '../shared/back_button.dart';
import '../shared/error_state.dart';
import 'home_feed.dart';
import 'home_screen.dart' show SeriesShelfCard;

/// Home's "See all": every series in progress across all servers, most
/// recently read first.
class InProgressScreen extends ConsumerWidget {
  const InProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(homeFeedProvider);
    final history = ref.watch(recentReadingProvider);
    final activeId = ref.watch(activeServerIdProvider);

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 12),
                  Text('In progress', style: AppText.largeTitle(size: 24)),
                ],
              ),
            ),
            Expanded(
              child: feedAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => AppErrorState(
                  error: e,
                  onRetry: () => ref.invalidate(homeFeedProvider),
                ),
                data: (feed) {
                  final items = orderByRecency(feed.inProgress, history, activeId);
                  if (items.isEmpty) {
                    return Center(
                      child: Text('Nothing in progress yet.',
                          style: AppText.body(color: AppColors.text60)),
                    );
                  }
                  final last = lastReadByKey(history, activeId);
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 130,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 13,
                      childAspectRatio: 0.52,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      return FadeSlideIn(
                        delay: Duration(milliseconds: 25 * math.min(i, 8)),
                        child: SeriesShelfCard(
                          item: item,
                          last: last[item.key],
                          width: double.infinity,
                          onTap: () async {
                            await activateServer(ref, item.serverId);
                            if (context.mounted) {
                              context.push('/series/${Uri.encodeComponent(item.series.id)}');
                            }
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
