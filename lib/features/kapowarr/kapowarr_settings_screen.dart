import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/kapowarr/kapowarr_client.dart';
import '../../core/kapowarr/kapowarr_config.dart';

class KapowarrSettingsScreen extends ConsumerStatefulWidget {
  const KapowarrSettingsScreen({super.key});

  @override
  ConsumerState<KapowarrSettingsScreen> createState() =>
      _KapowarrSettingsScreenState();
}

class _KapowarrSettingsScreenState
    extends ConsumerState<KapowarrSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();

  bool _testing = false;
  String? _testResult;
  bool? _testOk;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ref.read(kapowarrConfigStoreProvider).getWithApiKey().then((config) {
      if (config == null || !mounted) return;
      _urlController.text = config.baseUrl;
      _apiKeyController.text = config.apiKey;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  String get _normalizedUrl {
    var url = _urlController.text.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _testResult = null;
      _testOk = null;
    });
    final client = KapowarrClient(
      config: KapowarrConfig(
        baseUrl: _normalizedUrl,
        apiKey: _apiKeyController.text.trim(),
      ),
    );
    try {
      final stats = await client.getStats();
      setState(() {
        _testOk = true;
        _testResult = 'Connected - ${stats.volumes} volumes tracked.';
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
    await ref.read(kapowarrConfigStoreProvider).save(KapowarrConfig(
          baseUrl: _normalizedUrl,
          apiKey: _apiKeyController.text.trim(),
        ));
    ref.read(kapowarrConfigRevisionProvider.notifier).state++;
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kapowarr')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Kapowarr URL',
                hintText: 'http://100.108.109.63:5656',
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
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API key',
                hintText: 'Settings > General > API key in Kapowarr',
              ),
              obscureText: true,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _testing ? null : _test,
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
