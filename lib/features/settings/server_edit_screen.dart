import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../backends/kavita/kavita_backend.dart';
import '../../backends/komga/komga_backend.dart';
import '../../backends/opds/opds_backend.dart';
import '../../backends/suwayomi/suwayomi_backend.dart';
import '../../core/backend/reader_backend.dart';
import '../shared/back_button.dart';

class ServerEditScreen extends ConsumerStatefulWidget {
  final String? serverId;
  final ServerType? initialType;
  final bool isOnboarding;

  const ServerEditScreen({
    super.key,
    this.serverId,
    this.initialType,
    this.isOnboarding = false,
  });

  @override
  ConsumerState<ServerEditScreen> createState() => _ServerEditScreenState();
}

class _ServerEditScreenState extends ConsumerState<ServerEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  late ServerType _type = widget.initialType ?? ServerType.komga;

  bool _testing = false;
  String? _testResult;
  bool? _testOk;
  bool _saving = false;

  bool get _isEditing => widget.serverId != null;

  /// When the PWA is itself served from reader.shaddai.home (see
  /// deploy/Caddyfile.snippet), a Caddy reverse proxy makes Komga, Kavita,
  /// and Suwayomi reachable same-origin under /komga, /kavita, and
  /// /suwayomi - avoiding the browser CORS restriction that a bare
  /// Tailscale IP always hits. Direct IP entry still works fine for local
  /// dev. OPDS has no proxy path since it's not tied to a single fixed
  /// server the way the other three are.
  String? _sameOriginDefaultUrl(ServerType type) {
    if (Uri.base.host != 'reader.shaddai.home') return null;
    return switch (type) {
      ServerType.komga => '${Uri.base.origin}/komga',
      ServerType.kavita => '${Uri.base.origin}/kavita',
      ServerType.suwayomi => '${Uri.base.origin}/suwayomi',
      ServerType.opds => null,
    };
  }

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
    } else {
      final defaultUrl = _sameOriginDefaultUrl(_type);
      if (defaultUrl != null) _urlController.text = defaultUrl;
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
    final backend = switch (_type) {
      ServerType.komga =>
        KomgaBackend(config: config, password: _passwordController.text),
      ServerType.kavita =>
        KavitaBackend(config: config, password: _passwordController.text),
      ServerType.suwayomi =>
        SuwayomiBackend(config: config, password: _passwordController.text),
      ServerType.opds =>
        OpdsBackend(config: config, password: _passwordController.text),
    };

    try {
      await backend.authenticate();
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testResult = 'Connected successfully.';
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

  /// Raw exceptions (SocketException, DioException, etc.) are noisy and not
  /// actionable for a user typing in a URL - surface the likely cause
  /// instead of the exception's toString().
  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('connection refused') ||
        msg.contains('failed host lookup')) {
      return "Can't reach that address. Check the URL and that the server is running.";
    }
    if (msg.contains('401') || msg.contains('unauthorized')) {
      return 'Wrong username or password.';
    }
    if (msg.contains('404')) {
      return "That URL doesn't look like a $_serverTypeLabel server.";
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return 'Timed out waiting for a response. Check the server is reachable from this device.';
    }
    if (msg.contains('certificate') || msg.contains('handshake')) {
      return 'TLS certificate problem - if this is a self-signed cert, try http:// or trust the certificate first.';
    }
    return 'Connection failed: $e';
  }

  String get _serverTypeLabel => switch (_type) {
        ServerType.komga => 'Komga',
        ServerType.kavita => 'Kavita',
        ServerType.suwayomi => 'Suwayomi',
        ServerType.opds => 'OPDS',
      };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
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

      if (!mounted) return;
      if (widget.isOnboarding) {
        context.go('/home');
      } else {
        context.pop();
      }
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
                  Text(_isEditing ? 'Edit server' : 'Add server', style: AppText.largeTitle(size: 26)),
                ],
              ),
              const SizedBox(height: 20),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: [
                  for (final t in ServerType.values)
                    _TypeCard(
                      type: t,
                      selected: _type == t,
                      onTap: () => setState(() {
                        final wasDefault = _urlController.text.isEmpty ||
                            _urlController.text == _sameOriginDefaultUrl(_type);
                        _type = t;
                        if (!_isEditing && wasDefault) {
                          _urlController.text = _sameOriginDefaultUrl(_type) ?? '';
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _FormField(
                controller: _nameController,
                label: 'Display name',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              _FormField(
                controller: _urlController,
                label: 'Server URL',
                hint: _type == ServerType.opds
                    ? 'http://host:port/opds/v1.2/catalog'
                    : 'http://100.108.109.63:8081',
                keyboardType: TextInputType.url,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final uri = Uri.tryParse(v.trim());
                  if (uri == null || !uri.hasScheme) return 'Include http(s)://';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _FormField(
                controller: _usernameController,
                label: _type == ServerType.suwayomi
                    ? 'Username / email (unused - no auth)'
                    : 'Username / email',
                validator: (v) => _type != ServerType.suwayomi &&
                        (v == null || v.trim().isEmpty)
                    ? 'Required'
                    : null,
              ),
              const SizedBox(height: 12),
              _FormField(
                controller: _passwordController,
                label: _type == ServerType.suwayomi
                    ? 'Password (unused - no auth)'
                    : 'Password',
                obscureText: true,
                validator: (v) => _type != ServerType.suwayomi &&
                        (v == null || v.isEmpty)
                    ? 'Required'
                    : null,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testing ? null : _testConnection,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.text,
                        side: BorderSide(color: AppColors.borderStrong),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13)),
                      ),
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering, size: 18),
                      label: const Text('Test & continue'),
                    ),
                  ),
                ],
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
                      : Text('Save', style: AppText.body(size: 15, weight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final ServerType type;
  final bool selected;
  final VoidCallback onTap;
  const _TypeCard({required this.type, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.sourceColor(type.name);
    final label = switch (type) {
      ServerType.komga => 'Komga',
      ServerType.kavita => 'Kavita',
      ServerType.suwayomi => 'Suwayomi',
      ServerType.opds => 'OPDS',
    };
    return Material(
      color: selected ? AppColors.accent.withValues(alpha: 0.14) : AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AppColors.accent : AppColors.border),
          ),
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 9),
              Text(label, style: AppText.body(size: 14, weight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: AppText.body(size: 14),
      decoration: InputDecoration(
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
      ),
    );
  }
}
