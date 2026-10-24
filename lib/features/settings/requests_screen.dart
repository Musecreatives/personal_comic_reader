import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/kapowarr/kapowarr_client.dart';
import '../../core/sync/sync_client.dart';
import '../shared/back_button.dart';

/// Series friends asked for. The owner sees everyone's and adds or declines
/// them; a friend sees their own with where each one stands. Kapowarr's key
/// stays with the owner: adding runs on the owner's device.
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  late Future<List<SeriesRequest>> _future = _load();
  final _busy = <int>{};

  Future<List<SeriesRequest>> _load() => ref
      .read(syncClientProvider)
      .requests(all: ref.read(isOwnerProvider));

  void _reload() => setState(() => _future = _load());

  Future<void> _decide(SeriesRequest r, {required bool add}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(r.id));
    try {
      if (add) {
        final config = await ref.read(kapowarrConfigProvider.future);
        if (config == null || r.comicvineId == null) {
          throw Exception(config == null
              ? 'Set up Kapowarr on this device first'
              : 'This request has no ComicVine id; add it from Search');
        }
        await KapowarrClient(config: config).addVolume(r.comicvineId!);
      }
      await ref.read(syncClientProvider).decideRequest(r.id, add ? 'added' : 'declined');
      messenger.showSnackBar(SnackBar(
          content: Text(add ? 'Added ${r.title} to Kapowarr' : 'Declined ${r.title}')));
      _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't update the request: $e")));
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(isOwnerProvider);
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppScreenHeader(title: owner ? 'Requests' : 'My requests', titleSize: 28),
            Expanded(
              child: FutureBuilder<List<SeriesRequest>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return _Message(
                      text: "Couldn't load requests. Check your connection.",
                      action: TextButton(onPressed: _reload, child: const Text('Try again')),
                    );
                  }
                  final items = snap.data!;
                  if (items.isEmpty) {
                    return _Message(
                      text: owner
                          ? 'No requests yet. When friends ask for a series in Search, it shows up here.'
                          : 'Nothing asked for yet. Search for a comic and tap "Ask for this".',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _RequestTile(
                        request: items[i],
                        owner: owner,
                        busy: _busy.contains(items[i].id),
                        onAdd: () => _decide(items[i], add: true),
                        onDecline: () => _decide(items[i], add: false),
                      ),
                    ),
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

class _RequestTile extends StatelessWidget {
  final SeriesRequest request;
  final bool owner;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback onDecline;
  const _RequestTile({
    required this.request,
    required this.owner,
    required this.busy,
    required this.onAdd,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final r = request;
    final (label, color) = switch (r.status) {
      'added' => ('ADDED', AppColors.suwayomiText),
      'declined' => ('DECLINED', AppColors.text45),
      _ => ('WAITING', AppColors.warningText),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.year == null ? r.title : '${r.title} (${r.year})',
                  style: AppText.body(size: 15, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              Text(label, style: AppText.mono(size: 10.5, weight: FontWeight.w600, color: color)),
            ],
          ),
          if (owner && r.username != null) ...[
            const SizedBox(height: 4),
            Text('Asked by ${r.username}',
                style: AppText.body(size: 13, color: AppColors.text60)),
          ],
          if (owner && r.status == 'waiting') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: busy ? null : onAdd,
                  child: Text(busy ? 'Adding…' : 'Add to Kapowarr'),
                ),
                const SizedBox(width: 10),
                TextButton(onPressed: busy ? null : onDecline, child: const Text('Decline')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final Widget? action;
  const _Message({required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                textAlign: TextAlign.center,
                style: AppText.body(size: 14, color: AppColors.text60)),
            ?action,
          ],
        ),
      ),
    );
  }
}
