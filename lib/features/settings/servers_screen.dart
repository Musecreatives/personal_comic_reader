import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/backend/reader_backend.dart';

class ServersScreen extends ConsumerWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverListProvider);
    final activeId = ref.watch(activeServerIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Servers')),
      body: servers.isEmpty
          ? const _EmptyState()
          : ListView.builder(
              itemCount: servers.length,
              itemBuilder: (context, index) {
                final server = servers[index];
                final isActive = server.id == activeId;
                return ListTile(
                  leading: Icon(switch (server.type) {
                    ServerType.komga => Icons.local_library,
                    ServerType.kavita => Icons.menu_book,
                    ServerType.suwayomi => Icons.auto_stories,
                  }),
                  title: Text(server.name),
                  subtitle: Text('${server.type.name} • ${server.baseUrl}'),
                  trailing: isActive
                      ? const Chip(label: Text('Active'))
                      : TextButton(
                          onPressed: () async {
                            await ref
                                .read(serverStoreProvider)
                                .setActiveServerId(server.id);
                            ref.read(activeServerIdProvider.notifier).state =
                                server.id;
                            if (context.mounted) context.go('/home');
                          },
                          child: const Text('Use'),
                        ),
                  onTap: () => context.push('/settings/servers/${server.id}/edit'),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/settings/servers/new'),
        child: const Icon(Icons.add),
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
            const Icon(Icons.dns_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'No servers yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Add a Komga or Kavita server to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
