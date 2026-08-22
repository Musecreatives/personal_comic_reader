import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Servers'),
            subtitle: const Text('Add, edit, or switch between servers'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/servers'),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Kapowarr'),
            subtitle: const Text('Acquisition status - not a reading source'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/kapowarr'),
          ),
        ],
      ),
    );
  }
}
