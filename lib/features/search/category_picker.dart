import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/design_tokens.dart';
import '../shared/app_sheet.dart';
import '../shared/ink_chip.dart';

/// Thrown from an add action when the category picker was dismissed, so the
/// add is called off without an error.
class AddCancelled implements Exception {}

const _lastKey = 'add_categories_last';

/// Asks which categories a new title goes in, ticking the last choice.
/// Returns the chosen names (empty = Default), or throws [AddCancelled].
/// [existing] are the library's category names.
Future<List<String>> pickCategories(
    BuildContext context, List<String> existing) async {
  final prefs = await SharedPreferences.getInstance();
  final names = [
    for (final n in existing)
      if (n.trim().isNotEmpty && n != 'Default') n,
  ];
  final last = {
    for (final n in prefs.getStringList(_lastKey) ?? const <String>[])
      if (names.contains(n)) n,
  };
  if (!context.mounted) throw AddCancelled();
  final picked = await showAppSheet<List<String>>(
    context: context,
    grabber: true,
    isScrollControlled: true,
    builder: (_) => _CategorySheet(names: names, initial: last),
  );
  if (picked == null) throw AddCancelled();
  await prefs.setStringList(_lastKey, picked);
  return picked;
}

class _CategorySheet extends StatefulWidget {
  final List<String> names;
  final Set<String> initial;
  const _CategorySheet({required this.names, required this.initial});

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final _names = [...widget.names];
  late final _chosen = {...widget.initial};
  final _newName = TextEditingController();

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  void _addNew() {
    final n = _newName.text.trim();
    if (n.isEmpty || n == 'Default') return;
    setState(() {
      if (!_names.contains(n)) _names.add(n);
      _chosen.add(n);
      _newName.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add to which category?', style: AppText.heading()),
            const SizedBox(height: 4),
            Text(
              _chosen.isEmpty
                  ? 'None ticked: it goes in Default.'
                  : 'It goes in ${_chosen.join(', ')}.',
              style: AppText.body(color: AppColors.text60),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final n in _names)
                    CheckboxListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _chosen.contains(n),
                      title: Text(n, style: AppText.body(size: 15)),
                      onChanged: (v) => setState(
                          () => v == true ? _chosen.add(n) : _chosen.remove(n)),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newName,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'New category',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addNew(),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _addNew, child: const Text('Create')),
              ],
            ),
            const SizedBox(height: 16),
            InkButton(
              filled: true,
              label: 'Add to library',
              onTap: () => Navigator.pop(context, [
                for (final n in _names)
                  if (_chosen.contains(n)) n,
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
