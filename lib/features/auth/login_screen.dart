import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';

/// Sign in (or create an account) to shaddai-sync, the app's own small
/// cross-device sync service - separate from any Komga/Kavita/Suwayomi
/// server login. This is the very first screen the app can show: without
/// a session, nothing else (onboarding, home, a server's library) is
/// reachable, since History/Collections/Appearance/Stats all key off
/// whichever account is signed in.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _inviteCodeController = TextEditingController();

  bool _creatingAccount = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter a username and password.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final client = ref.read(syncClientProvider);
    try {
      final result = _creatingAccount
          ? await client.register(
              username: username,
              password: password,
              inviteCode: _inviteCodeController.text.trim(),
            )
          : await client.login(username: username, password: password);

      client.updateToken(result.token);
      await ref
          .read(authStoreProvider)
          .saveSession(token: result.token, username: result.username);
      ref.read(currentUsernameProvider.notifier).state = result.username;

      final historyStore = ref.read(historyStoreProvider);
      historyStore.attachSync(client, ref.read(syncQueueProvider));
      unawaited(historyStore.reconcile());

      if (mounted) context.go('/home');
    } catch (e) {
      setState(() => _error = _describeError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _describeError(Object e) {
    final message = e.toString();
    if (message.contains('403')) return 'Invalid invite code.';
    if (message.contains('409')) return 'That username is already taken.';
    if (message.contains('401')) return 'Wrong username or password.';
    if (message.contains('400')) {
      return 'Username required, password must be 8+ characters.';
    }
    return "Couldn't reach the sync service - check your connection.";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Shaddai Reader',
                      textAlign: TextAlign.center,
                      style: AppText.largeTitle(size: 28)),
                  const SizedBox(height: 8),
                  Text(
                    _creatingAccount
                        ? 'Create your account to sync history and settings across devices.'
                        : 'Sign in to sync your history and settings across devices.',
                    textAlign: TextAlign.center,
                    style: AppText.body(size: 14, color: AppColors.text60),
                  ),
                  const SizedBox(height: 28),
                  _Field(controller: _usernameController, label: 'Username'),
                  const SizedBox(height: 12),
                  _Field(
                    controller: _passwordController,
                    label: 'Password',
                    obscure: true,
                  ),
                  if (_creatingAccount) ...[
                    const SizedBox(height: 12),
                    _Field(
                      controller: _inviteCodeController,
                      label: 'Invite code',
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, style: AppText.body(size: 13, color: AppColors.dangerText)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_creatingAccount ? 'Create account' : 'Sign in',
                            style: AppText.body(size: 15, weight: FontWeight.w600, color: Colors.white)),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                              _creatingAccount = !_creatingAccount;
                              _error = null;
                            }),
                    child: Text(
                      _creatingAccount
                          ? 'Already have an account? Sign in'
                          : "Don't have an account? Create one",
                      style: AppText.body(size: 13, color: AppColors.accentLink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  const _Field({required this.controller, required this.label, this.obscure = false});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: AppText.body(size: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppText.body(size: 13, color: AppColors.text45),
        filled: true,
        fillColor: AppColors.fillSubtle,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}
