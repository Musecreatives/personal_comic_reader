import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../shared/back_button.dart';

/// The optional ComicVine API key behind "Find on ComicVine" for imported
/// comics. ComicVine is only ever asked when the user runs a lookup.
class ComicVineSettingsScreen extends ConsumerStatefulWidget {
  const ComicVineSettingsScreen({super.key});

  @override
  ConsumerState<ComicVineSettingsScreen> createState() =>
      _ComicVineSettingsScreenState();
}

class _ComicVineSettingsScreenState
    extends ConsumerState<ComicVineSettingsScreen> {
  final _keyController = TextEditingController();
  bool _hasKey = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ref.read(comicVineKeyStoreProvider).get().then((key) {
      if (!mounted || key == null) return;
      setState(() {
        _keyController.text = key;
        _hasKey = true;
      });
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = ref.read(comicVineKeyStoreProvider);
    final key = _keyController.text.trim();
    setState(() => _saving = true);
    try {
      key.isEmpty ? await store.clear() : await store.save(key);
      if (mounted) context.popOrHome();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
          children: [
            Row(
              children: [
                const AppBackButton(),
                const SizedBox(width: 12),
                Text('ComicVine', style: AppText.largeTitle(size: 26)),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Optional. Lets "Find on ComicVine" fill in the summary, '
                'publisher, year and credits of comics you imported. Get a '
                'free key at comicvine.gamespot.com/api.',
                style: AppText.body(size: 12.5, color: AppColors.text45),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _keyController,
              obscureText: true,
              onChanged: (_) => setState(() {}),
              style: AppText.body(size: 14),
              decoration: InputDecoration(
                labelText: 'API key',
                hintText: 'Leave empty to remove',
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
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              onPressed: _saving ? null : _save,
              child: Text(
                _hasKey && _keyController.text.trim().isEmpty
                    ? 'Remove key'
                    : 'Save',
                style: AppText.body(
                  size: 15,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
