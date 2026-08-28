import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/backend/reader_backend.dart';

class ServersScreen extends ConsumerWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverListProvider);
    final activeId = ref.watch(activeServerIdProvider);

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Sources', style: AppText.largeTitle()),
                  Material(
                    color: AppColors.accent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => context.push('/settings/servers/new'),
                      child: const SizedBox(
                        width: 34,
                        height: 34,
                        child: Icon(Icons.add, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: servers.isEmpty
                  ? const _EmptyState()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      children: [
                        for (final server in servers)
                          _ServerCard(
                            name: server.name,
                            type: server.type,
                            baseUrl: server.baseUrl,
                            isActive: server.id == activeId,
                            onUse: () async {
                              await ref
                                  .read(serverStoreProvider)
                                  .setActiveServerId(server.id);
                              ref.read(activeServerIdProvider.notifier).state =
                                  server.id;
                              if (context.mounted) context.go('/home');
                            },
                            onTap: () =>
                                context.push('/settings/servers/${server.id}/edit'),
                          ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => context.push('/settings/import-backup'),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.borderStrong),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Import from Paperback',
                                    style: AppText.body(size: 13.5, weight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                Text(
                                  "Drop a .pas5 backup to map its library and read history onto Suwayomi.",
                                  style: AppText.body(size: 11.5, color: AppColors.text.withValues(alpha: 0.5)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  final String name;
  final ServerType type;
  final String baseUrl;
  final bool isActive;
  final VoidCallback onUse;
  final VoidCallback onTap;

  const _ServerCard({
    required this.name,
    required this.type,
    required this.baseUrl,
    required this.isActive,
    required this.onUse,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.sourceColor(type.name);
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? color.withValues(alpha: 0.4) : AppColors.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppText.body(size: 15, weight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  Text('${type.name.toUpperCase()} · $baseUrl',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.mono(size: 9.5)),
                ],
              ),
            ),
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.suwayomi.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('ACTIVE', style: AppText.mono(size: 9, color: AppColors.suwayomiText)),
              )
            else
              Material(
                color: AppColors.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onUse,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text('Use',
                        style: AppText.body(
                            size: 11.5, weight: FontWeight.w600, color: AppColors.accentLink)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 48, color: AppColors.text45),
            const SizedBox(height: 12),
            Text('No servers yet', style: AppText.heading(size: 18)),
            const SizedBox(height: 4),
            Text(
              'Add a Komga, Kavita, Suwayomi or OPDS server to get started.',
              textAlign: TextAlign.center,
              style: AppText.body(color: AppColors.text45),
            ),
          ],
        ),
      ),
    );
  }
}
