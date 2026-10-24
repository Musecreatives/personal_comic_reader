import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/sync/sync_client.dart';
import '../shared/back_button.dart';

/// Owner only: one code per friend. Each works once; an unused one can be
/// revoked. The link opens the download page with the code filled in.
class InvitesScreen extends ConsumerStatefulWidget {
  const InvitesScreen({super.key});

  @override
  ConsumerState<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends ConsumerState<InvitesScreen> {
  late Future<List<Invite>> _future = _load();
  final _note = TextEditingController();
  bool _creating = false;

  Future<List<Invite>> _load() => ref.read(syncClientProvider).invites();

  void _reload() => setState(() => _future = _load());

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _copy(Invite i) {
    Clipboard.setData(ClipboardData(
        text: 'Your Shaddai Reader invite code: ${i.code}\nGet the app: ${i.link}'));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Invite copied - paste it to your friend')));
  }

  Future<void> _create() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _creating = true);
    try {
      final invite = await ref.read(syncClientProvider).createInvite(_note.text.trim());
      _note.clear();
      _copy(invite);
      _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't make an invite: $e")));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _revoke(Invite i) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(syncClientProvider).revokeInvite(i.code);
      _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't revoke: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppScreenHeader(title: 'Invite friends', titleSize: 28),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _note,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _creating ? null : _create(),
                      decoration: const InputDecoration(
                        labelText: "Who's it for? (optional)",
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _creating ? null : _create,
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: Text(_creating ? 'Making…' : 'Invite'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Invite>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: TextButton(
                          onPressed: _reload,
                          child: const Text("Couldn't load invites. Try again")),
                    );
                  }
                  final items = snap.data!;
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No invites yet. Each friend gets their own code; it works once.',
                          textAlign: TextAlign.center,
                          style: AppText.body(size: 14, color: AppColors.text60),
                        ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _InviteTile(
                        invite: items[i],
                        onCopy: () => _copy(items[i]),
                        onRevoke: () => _revoke(items[i]),
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

class _InviteTile extends StatelessWidget {
  final Invite invite;
  final VoidCallback onCopy;
  final VoidCallback onRevoke;
  const _InviteTile({required this.invite, required this.onCopy, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final i = invite;
    final (label, color) = switch (i.status) {
      'used' => ('JOINED', AppColors.suwayomiText),
      'revoked' => ('REVOKED', AppColors.text45),
      _ => ('UNUSED', AppColors.warningText),
    };
    final who = i.status == 'used' ? 'Joined as ${i.usedBy}' : i.note;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SelectableText(i.code,
                        style: AppText.mono(size: 15, weight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    Text(label,
                        style: AppText.mono(size: 10.5, weight: FontWeight.w600, color: color)),
                  ],
                ),
                if (who.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(who, style: AppText.body(size: 13, color: AppColors.text60)),
                ],
              ],
            ),
          ),
          if (i.status == 'unused') ...[
            IconButton(
              tooltip: 'Copy invite',
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 19),
            ),
            IconButton(
              tooltip: 'Revoke',
              onPressed: onRevoke,
              icon: const Icon(Icons.block, size: 19),
            ),
          ],
        ],
      ),
    );
  }
}
