import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../backends/kavita/kavita_backend.dart';
import '../../backends/komga/komga_backend.dart';
import '../../core/backend/reader_backend.dart';

class ServerEditScreen extends ConsumerStatefulWidget {
  final String? serverId;

  const ServerEditScreen({super.key, this.serverId});

  @override
  ConsumerState<ServerEditScreen> createState() => _ServerEditScreenState();
}

class _ServerEditScreenState extends ConsumerState<ServerEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  ServerType _type = ServerType.komga;

  bool _testing = false;
  String? _testResult;
  bool? _testOk;
  bool _saving = false;

  bool get _isEditing => widget.serverId != null;

  @override
  void initState() {
    super.initState();
    if (widget.serverId != null) {
      final existing = ref.read(serverStoreProvider).getServer(widget.serverId!);
      if (existing != null) {
        _nameController.text = existing.name;
        _urlController.text = existing.baseUrl;
        _usernameController.text = existing.username;
        _type = existing.type;
        ref
            .read(serverStoreProvider)
            .getPassword(existing.id)
            .then((p) => _passwordController.text = p ?? '');
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _normalizedUrl {
    var url = _urlController.text.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  ServerConfig _buildConfig(String id) => ServerConfig(
        id: id,
        name: _nameController.text.trim(),
        type: _type,
        baseUrl: _normalizedUrl,
        username: _usernameController.text.trim(),
      );

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _testResult = null;
      _testOk = null;
    });

    final config = _buildConfig('__test__');
    final backend = _type == ServerType.komga
        ? KomgaBackend(config: config, password: _passwordController.text)
        : KavitaBackend(config: config, password: _passwordController.text);

    try {
      await backend.authenticate();
      setState(() {
        _testOk = true;
        _testResult = 'Connected successfully.';
      });
    } on BackendNotImplemented {
      setState(() {
        _testOk = null;
        _testResult = 'Kavita support lands in Phase 3 - can\'t test yet.';
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = 'Connection failed: $e';
      });
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final id = widget.serverId ?? const Uuid().v4();
    final config = _buildConfig(id);
    final store = ref.read(serverStoreProvider);
    await store.saveServer(config, password: _passwordController.text);

    // First server added becomes active automatically.
    if (store.getActiveServerId() == null) {
      await store.setActiveServerId(id);
      ref.read(activeServerIdProvider.notifier).state = id;
    }

    ref.read(serverListRevisionProvider.notifier).state++;

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit server' : 'Add server')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<ServerType>(
              segments: const [
                ButtonSegment(value: ServerType.komga, label: Text('Komga')),
                ButtonSegment(value: ServerType.kavita, label: Text('Kavita')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Display name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://100.108.109.63:8081',
              ),
              keyboardType: TextInputType.url,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                final uri = Uri.tryParse(v.trim());
                if (uri == null || !uri.hasScheme) return 'Include http(s)://';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username / email'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _testing ? null : _testConnection,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: const Text('Test connection'),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Text(
                _testResult!,
                style: TextStyle(
                  color: _testOk == true
                      ? Colors.greenAccent
                      : _testOk == false
                          ? Colors.redAccent
                          : Colors.orangeAccent,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
