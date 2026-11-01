import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/debug/problem_reports.dart';
import '../shared/app_sheet.dart';

/// Around the whole app (main.dart), so a report can show the screen it
/// came from.
final screenBoundaryKey = GlobalKey();

/// The screen as a PNG about 540px wide, small enough to ride in a ticket.
Future<Uint8List?> _captureScreen() async {
  final boundary = screenBoundaryKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary || boundary.size.width == 0) {
    return null;
  }
  try {
    final image = await boundary.toImage(
      pixelRatio: (540 / boundary.size.width).clamp(0.2, 2.0),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// "Report a problem": what happened, a picture of the screen, plus (by
/// default) recent logs and network calls, sent to the sync server as a
/// ticket. [error] prefills a crash report from an error screen.
Future<void> showReportSheet(BuildContext context, {Object? error}) async {
  String? route;
  try {
    route = GoRouter.of(
      context,
    ).routerDelegate.currentConfiguration.uri.toString();
  } catch (_) {}
  // Before the sheet covers it.
  final screenshot = await _captureScreen();
  if (!context.mounted) return;
  return showAppSheet<void>(
    context: context,
    grabber: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.card,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) =>
        _ReportSheet(error: error, route: route, screenshot: screenshot),
  );
}

class _ReportSheet extends ConsumerStatefulWidget {
  final Object? error;
  final String? route;
  final Uint8List? screenshot;
  const _ReportSheet({this.error, this.route, this.screenshot});

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  late var _kind = widget.error == null ? ReportKind.problem : ReportKind.crash;
  late final _title = TextEditingController(
    text: widget.error == null ? '' : '${widget.error}'.split('\n').first,
  );
  final _details = TextEditingController();
  var _attach = true;
  late var _attachScreen = widget.screenshot != null;
  var _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    Map<String, dynamic> report({required bool withScreen}) => buildReport(
      kind: _kind,
      title: _title.text.trim(),
      details: _details.text.trim(),
      route: widget.route,
      error: widget.error?.toString(),
      includeDiagnostics: _attach,
      screenshot: withScreen ? widget.screenshot : null,
    );
    final client = ref.read(syncClientProvider);
    try {
      var note = '';
      try {
        await sendReport(client, report(withScreen: _attachScreen));
      } catch (_) {
        // A server that refuses a large body still gets the words.
        if (!_attachScreen) rethrow;
        await sendReport(client, report(withScreen: false));
        note = ' (without the screenshot)';
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Report sent$note. Replies show up under Settings → Diagnostics & reports.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't send the report: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppColors.fillSubtle,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Report a problem',
              style: AppText.body(size: 17, weight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            SegmentedButton<ReportKind>(
              segments: const [
                ButtonSegment(
                  value: ReportKind.problem,
                  label: Text('Problem'),
                ),
                ButtonSegment(value: ReportKind.crash, label: Text('Crash')),
                ButtonSegment(value: ReportKind.idea, label: Text('Idea')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              autofocus: widget.error == null,
              style: AppText.body(size: 14),
              decoration: field('What went wrong, in a line'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _details,
              minLines: 3,
              maxLines: 8,
              style: AppText.body(size: 13.5),
              decoration: field('What you did before it happened (optional)'),
            ),
            const SizedBox(height: 6),
            if (widget.screenshot != null)
              CheckboxListTile(
                value: _attachScreen,
                onChanged: (v) => setState(() => _attachScreen = v ?? true),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Attach a screenshot of this screen',
                  style: AppText.body(size: 13),
                ),
                secondary: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    widget.screenshot!,
                    height: 56,
                    semanticLabel: 'Screenshot to attach',
                  ),
                ),
              ),
            CheckboxListTile(
              value: _attach,
              onChanged: (v) => setState(() => _attach = v ?? true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Attach recent logs and network activity',
                style: AppText.body(size: 13),
              ),
              subtitle: Text(
                'No passwords or API keys are included',
                style: AppText.body(size: 11.5, color: AppColors.text45),
              ),
            ),
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: _title,
              builder: (context, _) => FilledButton(
                onPressed: _sending || _title.text.trim().isEmpty
                    ? null
                    : _send,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child: Text(_sending ? 'Sending…' : 'Send report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
