import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/kapowarr/kapowarr_client.dart';
import '../../core/kapowarr/kapowarr_config.dart';
import '../shared/back_button.dart';

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
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testResult = 'Connected - ${stats.volumes} volumes tracked.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = _friendlyError(e);
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('connection refused') ||
        msg.contains('failed host lookup')) {
      return "Can't reach that address. Check the URL and that Kapowarr is running.";
    }
    if (msg.contains('401') || msg.contains('403')) {
      return 'That API key was rejected.';
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return 'Timed out waiting for a response.';
    }
    return 'Connection failed: $e';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(kapowarrConfigStoreProvider).save(KapowarrConfig(
            baseUrl: _normalizedUrl,
            apiKey: _apiKeyController.text.trim(),
          ));
      ref.read(kapowarrConfigRevisionProvider.notifier).state++;
      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = 'Could not save: ${_friendlyError(e)}';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            children: [
              Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 12),
                  Text('Kapowarr', style: AppText.largeTitle(size: 26)),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _urlController,
                style: AppText.body(size: 14),
                decoration: _fieldDecoration('Kapowarr URL', hint: 'http://100.108.109.63:5656'),
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
                style: AppText.body(size: 14),
                decoration: _fieldDecoration('API key',
                    hint: 'Settings > General > API key in Kapowarr'),
                obscureText: true,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _testing ? null : _test,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.text,
                  side: BorderSide(color: AppColors.borderStrong),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                ),
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering, size: 18),
                label: const Text('Test connection'),
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(
                    color: (_testOk == true ? AppColors.suwayomi : AppColors.danger)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: (_testOk == true ? AppColors.suwayomi : AppColors.danger)
                          .withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    _testResult!,
                    style: AppText.body(
                      size: 12.5,
                      color: _testOk == true ? AppColors.suwayomiText : AppColors.dangerText,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text('Save',
                          style: AppText.body(size: 15, weight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: AppText.body(size: 13, color: AppColors.text45),
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: AppColors.accent),
        ),
      );
}
