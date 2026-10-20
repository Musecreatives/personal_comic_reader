import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../backends/local/local_library_store.dart';

/// "Edit details" for an imported series: title, summary, credits,
/// publisher, year and genres. Returns the edited record for the caller to
/// save, or null if dismissed - nothing is written here. [initial] may be
/// pre-filled (e.g. from a ComicVine match) and differ from what's stored.
Future<LocalSeriesRecord?> showEditDetailsSheet(
  BuildContext context,
  LocalSeriesRecord initial, {
  String heading = 'Edit details',
}) {
  return showModalBottomSheet<LocalSeriesRecord>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: Motion.sheetStyle,
    backgroundColor: AppColors.card,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _EditDetailsSheet(initial: initial, heading: heading),
  );
}

class _EditDetailsSheet extends StatefulWidget {
  final LocalSeriesRecord initial;
  final String heading;
  const _EditDetailsSheet({required this.initial, required this.heading});

  @override
  State<_EditDetailsSheet> createState() => _EditDetailsSheetState();
}

class _EditDetailsSheetState extends State<_EditDetailsSheet> {
  late final _title = TextEditingController(text: widget.initial.title);
  late final _summary = TextEditingController(text: widget.initial.summary);
  late final _writer = TextEditingController(text: widget.initial.writer);
  late final _artist = TextEditingController(text: widget.initial.artist);
  late final _publisher =
      TextEditingController(text: widget.initial.publisher);
  late final _year = TextEditingController(text: widget.initial.year);
  late final _genres =
      TextEditingController(text: widget.initial.genres.join(', '));

  @override
  void dispose() {
    for (final c in [
      _title, _summary, _writer, _artist, _publisher, _year, _genres,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    String? text(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    Navigator.pop(
      context,
      widget.initial.withDetails(
        title: _title.text.trim(),
        summary: text(_summary),
        writer: text(_writer),
        artist: text(_artist),
        publisher: text(_publisher),
        year: text(_year),
        genres: _genres.text
            .split(',')
            .map((g) => g.trim())
            .where((g) => g.isNotEmpty)
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String label, {String? hint}) => InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: AppText.body(size: 13, color: AppColors.text45),
          filled: true,
          fillColor: AppColors.fillSubtle,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        );
    Widget row(List<Widget> children) => Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: children[i]),
            ],
          ],
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.heading, style: AppText.heading(size: 18)),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              style: AppText.body(size: 14),
              decoration: field('Title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _summary,
              minLines: 3,
              maxLines: 8,
              style: AppText.body(size: 13.5),
              decoration: field('Summary'),
            ),
            const SizedBox(height: 10),
            row([
              TextField(
                controller: _writer,
                style: AppText.body(size: 14),
                decoration: field('Writer'),
              ),
              TextField(
                controller: _artist,
                style: AppText.body(size: 14),
                decoration: field('Artist'),
              ),
            ]),
            const SizedBox(height: 10),
            row([
              TextField(
                controller: _publisher,
                style: AppText.body(size: 14),
                decoration: field('Publisher'),
              ),
              TextField(
                controller: _year,
                keyboardType: TextInputType.number,
                style: AppText.body(size: 14),
                decoration: field('Year'),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _genres,
              style: AppText.body(size: 14),
              decoration: field('Genres', hint: 'Superhero, Sci-Fi'),
            ),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: _title,
              builder: (context, _) => FilledButton(
                onPressed: _title.text.trim().isEmpty ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
