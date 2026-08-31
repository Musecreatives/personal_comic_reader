import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../backends/suwayomi/suwayomi_maintenance_client.dart';
import '../../core/backend/reader_backend.dart';
import '../shared/back_button.dart';
import '../shared/error_state.dart';

/// Suwayomi health/repair panel (6f) - built after a real incident where
/// fixing a wedged mergerfs mount required 20+ manual SSH/GraphQL calls to
/// spot that extensions had silently lost their install records and the
/// database needed restoring from Suwayomi's own backups. This surfaces
/// the same checks and actions in-app so that doesn't need a terminal
/// next time.
class SuwayomiMaintenanceScreen extends ConsumerStatefulWidget {
  const SuwayomiMaintenanceScreen({super.key});

  @override
  ConsumerState<SuwayomiMaintenanceScreen> createState() => _SuwayomiMaintenanceScreenState();
}

class _SuwayomiMaintenanceScreenState extends ConsumerState<SuwayomiMaintenanceScreen> {
  SuwayomiMaintenanceClient? _client;
  Future<(LibraryHealth, List<ExtensionStatus>)>? _future;
  final Set<String> _reinstalling = {};
  String? _actionMessage;
  bool _creatingBackup = false;
  bool _restoring = false;

  Future<(LibraryHealth, List<ExtensionStatus>)> _load(SuwayomiMaintenanceClient client) async {
    final health = await client.libraryHealth();
    final extensions = await client.extensionStatus();
    return (health, extensions);
  }

  void _ensureClient(ServerConfig config) {
    if (_client != null) return;
    _client = SuwayomiMaintenanceClient(config: config);
    _future = _load(_client!);
  }

  Future<void> _reinstall(String pkgName) async {
    setState(() {
      _reinstalling.add(pkgName);
      _actionMessage = null;
    });
    try {
      await _client!.reinstallExtension(pkgName);
      setState(() => _future = _load(_client!));
      await _future;
    } catch (e) {
      setState(() => _actionMessage = '$e');
    } finally {
      if (mounted) setState(() => _reinstalling.remove(pkgName));
    }
  }

  Future<void> _createBackup() async {
    setState(() {
      _creatingBackup = true;
      _actionMessage = null;
    });
    try {
      final url = await _client!.createBackup();
      setState(() => _actionMessage = 'Backup created on the server: $url');
    } catch (e) {
      setState(() => _actionMessage = "Couldn't create a backup: $e");
    } finally {
      if (mounted) setState(() => _creatingBackup = false);
    }
  }

  Future<void> _restoreFromFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['tachibk'],
    );
    if (files.isEmpty || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Restore from backup?', style: AppText.body(size: 16, weight: FontWeight.w600)),
        content: Text(
          'This replaces the current Suwayomi library with whatever is in "${files.single.name}". '
          'This cannot be undone from here.',
          style: AppText.body(size: 13, color: AppColors.text60),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Restore', style: TextStyle(color: AppColors.dangerText)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _restoring = true;
      _actionMessage = null;
    });
    try {
      final bytes = await files.single.readAsBytes();
      await _client!.restoreBackup(bytes, filename: files.single.name);
      setState(() {
        _actionMessage = 'Restore complete.';
        _future = _load(_client!);
      });
      await _future;
    } catch (e) {
      setState(() => _actionMessage = "Restore didn't finish: $e");
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backendAsync = ref.watch(activeBackendProvider);

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
                  Text('Suwayomi', style: AppText.largeTitle()),
                ],
              ),
            ),
            Expanded(
              child: backendAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) =>
                    AppErrorState(error: e, onRetry: () => ref.invalidate(activeBackendProvider)),
                data: (backend) {
                  if (backend == null || backend.config.type != ServerType.suwayomi) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Switch to a Suwayomi server (Settings → Servers) to see maintenance here.',
                          textAlign: TextAlign.center,
                          style: AppText.body(color: AppColors.text45),
                        ),
                      ),
                    );
                  }
                  _ensureClient(backend.config);
                  return _Body(
                    future: _future!,
                    reinstalling: _reinstalling,
                    onReinstall: _reinstall,
                    actionMessage: _actionMessage,
                    creatingBackup: _creatingBackup,
                    restoring: _restoring,
                    onCreateBackup: _createBackup,
                    onRestore: _restoreFromFile,
                    onRetry: () => setState(() => _future = _load(_client!)),
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

class _Body extends StatelessWidget {
  final Future<(LibraryHealth, List<ExtensionStatus>)> future;
  final Set<String> reinstalling;
  final Future<void> Function(String pkgName) onReinstall;
  final String? actionMessage;
  final bool creatingBackup;
  final bool restoring;
  final VoidCallback onCreateBackup;
  final VoidCallback onRestore;
  final VoidCallback onRetry;

  const _Body({
    required this.future,
    required this.reinstalling,
    required this.onReinstall,
    required this.actionMessage,
    required this.creatingBackup,
    required this.restoring,
    required this.onCreateBackup,
    required this.onRestore,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(LibraryHealth, List<ExtensionStatus>)>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(error: snapshot.error!, onRetry: onRetry);
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (health, extensions) = snapshot.data!;
        final missing = extensions.where((e) => !e.isInstalled).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.suwayomi.withValues(alpha: 0.12), AppColors.card],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.suwayomi.withValues(alpha: 0.2)),
              ),
              child: Wrap(
                spacing: 22,
                runSpacing: 14,
                children: [
                  _StatTile(value: '${health.totalManga}', label: 'MANGA'),
                  _StatTile(value: '${health.categoryCount}', label: 'CATEGORIES'),
                  _StatTile(
                    value: '${extensions.length - missing.length}/${extensions.length}',
                    label: 'EXTENSIONS OK',
                    valueColor: missing.isEmpty ? null : AppColors.dangerText,
                  ),
                ],
              ),
            ),
            if (actionMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.fillSubtle,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(actionMessage!, style: AppText.body(size: 12.5, color: AppColors.text60)),
              ),
            ],
            const SizedBox(height: 22),
            Text('EXTENSIONS', style: AppText.sectionLabel()),
            const SizedBox(height: 10),
            for (final ext in extensions)
              _ExtensionRow(
                extension: ext,
                busy: reinstalling.contains(ext.pkgName),
                onReinstall: ext.isInstalled ? null : () => onReinstall(ext.pkgName),
              ),
            const SizedBox(height: 22),
            Text('BACKUP', style: AppText.sectionLabel()),
            const SizedBox(height: 10),
            _ActionRow(
              icon: Icons.save_outlined,
              label: 'Create backup now',
              busy: creatingBackup,
              onTap: onCreateBackup,
            ),
            const SizedBox(height: 8),
            _ActionRow(
              icon: Icons.restore_outlined,
              label: 'Restore from file',
              danger: true,
              busy: restoring,
              onTap: onRestore,
            ),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;
  const _StatTile({required this.value, required this.label, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppText.heading(size: 19, color: valueColor ?? AppColors.text)),
          const SizedBox(height: 6),
          Text(label, style: AppText.mono(size: 9)),
        ],
      ),
    );
  }
}

class _ExtensionRow extends StatelessWidget {
  final ExtensionStatus extension;
  final bool busy;
  final VoidCallback? onReinstall;
  const _ExtensionRow({required this.extension, required this.busy, required this.onReinstall});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: extension.isInstalled ? AppColors.suwayomiText : AppColors.dangerText,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(child: Text(extension.name, style: AppText.body(size: 13.5))),
          if (busy)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          else if (onReinstall != null)
            TextButton(
              onPressed: onReinstall,
              child: Text('Reinstall', style: AppText.body(size: 12, weight: FontWeight.w600, color: AppColors.accentLink)),
            ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final bool busy;
  final VoidCallback onTap;
  const _ActionRow({
    required this.icon,
    required this.label,
    this.danger = false,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.dangerText : AppColors.text;
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 11),
            Expanded(child: Text(label, style: AppText.body(size: 14, weight: FontWeight.w500, color: color))),
            if (busy)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(Icons.chevron_right, size: 18, color: AppColors.text30),
          ],
        ),
      ),
    );
  }
}
