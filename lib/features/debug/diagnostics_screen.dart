import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/debug/debug_log.dart';
import '../../core/debug/problem_reports.dart';
import '../shared/back_button.dart';
import 'report_sheet.dart';

enum _Tab { network, logs, reports }

/// Network calls, logs and your problem reports - the in-app inspector.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  var _tab = _Tab.network;
  var _failuresOnly = false;
  Future<List<ProblemReport>>? _reports;

  final _log = DebugLog.instance;

  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (_tab == _Tab.reports) {
      _reports ??= listReports(ref.read(syncClientProvider));
    }
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppScreenHeader(
              title: 'Diagnostics',
              trailing: TextButton.icon(
                onPressed: () => showReportSheet(context),
                icon: const Icon(Icons.bug_report_outlined, size: 18),
                label: const Text('Report a problem'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: ValueListenableBuilder(
                valueListenable: _log.debugMode,
                builder: (context, on, _) => SwitchListTile(
                  value: on,
                  onChanged: _log.setDebugMode,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Debug mode', style: AppText.body(size: 14)),
                  subtitle: Text(
                      'A bug button floats over every screen, for reporting '
                      'right where something breaks',
                      style: AppText.body(size: 11.5, color: AppColors.text45)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<_Tab>(
                      segments: const [
                        ButtonSegment(value: _Tab.network, label: Text('Network')),
                        ButtonSegment(value: _Tab.logs, label: Text('Logs')),
                        ButtonSegment(value: _Tab.reports, label: Text('Reports')),
                      ],
                      selected: {_tab},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _tab = s.first),
                    ),
                  ),
                  if (_tab != _Tab.reports) ...[
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Failures'),
                      selected: _failuresOnly,
                      onSelected: (v) => setState(() => _failuresOnly = v),
                    ),
                    IconButton(
                      tooltip: 'Clear',
                      onPressed: _log.clear,
                      icon: Icon(Icons.delete_sweep_outlined, color: AppColors.text60),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: switch (_tab) {
                    _Tab.reports => _reportsList(),
                    _ => ListenableBuilder(
                        listenable: _log,
                        builder: (context, _) =>
                            _tab == _Tab.network ? _networkList() : _logsList(),
                      ),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(String text) => Center(
      child: Text(text, style: AppText.body(color: AppColors.text45)));

  Widget _networkList() {
    final items = _log.network
        .where((e) => !_failuresOnly || e.failed)
        .toList()
        .reversed
        .toList();
    if (items.isEmpty) return _empty('No network calls yet.');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final e = items[i];
        final color = e.pending
            ? AppColors.text45
            : e.failed
                ? AppColors.dangerText
                : AppColors.suwayomiText;
        return _ExpandableRow(
          leading: SizedBox(
            width: 44,
            child: Text(e.pending ? '…' : '${e.status ?? 'ERR'}',
                style: AppText.mono(size: 11, color: color)),
          ),
          title: '${e.method} ${e.uri.host}${e.uri.path}',
          subtitle: [
            _time(e.at),
            if (e.duration != null) '${e.duration!.inMilliseconds} ms',
            if (e.bytes != null) '${(e.bytes! / 1024).toStringAsFixed(0)} KB',
            if (e.error != null) e.error!,
          ].join(' · '),
          detail: [
            '${e.method} ${e.uri}',
            if (e.requestBody != null) '\nRequest:\n${e.requestBody}',
            if (e.responseBody != null) '\nResponse:\n${e.responseBody}',
          ].join('\n'),
        );
      },
    );
  }

  Widget _logsList() {
    final items = _log.logs
        .where((e) => !_failuresOnly || e.level == LogLevel.error)
        .toList()
        .reversed
        .toList();
    if (items.isEmpty) return _empty('Nothing logged yet.');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final e = items[i];
        return _ExpandableRow(
          leading: Container(
            width: 4,
            height: 28,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: switch (e.level) {
                LogLevel.error => AppColors.danger,
                LogLevel.warning => AppColors.kavitaText,
                LogLevel.info => AppColors.track,
              },
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          title: e.message.split('\n').first,
          subtitle: _time(e.at),
          detail: [e.message, if (e.stack != null) '\n${e.stack}'].join('\n'),
        );
      },
    );
  }

  Widget _reportsList() {
    return FutureBuilder<List<ProblemReport>>(
      future: _reports,
      builder: (context, snap) {
        if (snap.hasError) return _empty("Couldn't load your reports: ${snap.error}");
        final reports = snap.data;
        if (reports == null) return const Center(child: CircularProgressIndicator());
        if (reports.isEmpty) return _empty('You haven\'t sent any reports.');
        return RefreshIndicator(
          onRefresh: () async {
            final next = listReports(ref.read(syncClientProvider));
            setState(() => _reports = next);
            await next;
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            itemCount: reports.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _ReportCard(report: reports[i]),
          ),
        );
      },
    );
  }
}

class _ExpandableRow extends StatefulWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final String detail;
  const _ExpandableRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.detail,
  });

  @override
  State<_ExpandableRow> createState() => _ExpandableRowState();
}

class _ExpandableRowState extends State<_ExpandableRow> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      hoverColor: AppColors.fillHover,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                widget.leading,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(size: 12.5)),
                      const SizedBox(height: 2),
                      Text(widget.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.mono(size: 10, color: AppColors.text45)),
                    ],
                  ),
                ),
              ],
            ),
            if (_open) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(widget.detail,
                    style: AppText.mono(size: 10.5, color: AppColors.text60)),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: widget.detail)),
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('Copy'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final ProblemReport report;
  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (report.status) {
      'fixed' => ('Fixed', AppColors.suwayomiText),
      'in_progress' => ('Being worked on', AppColors.kavitaText),
      'closed' => ('Closed', AppColors.text45),
      _ => ('Open', AppColors.accentLink),
    };
    final d = report.createdAt.toLocal();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(report.title,
                    style: AppText.body(size: 14, weight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(label, style: AppText.mono(size: 9.5, color: color)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${report.kind.name.toUpperCase()} · ${d.day}/${d.month}/${d.year}',
              style: AppText.mono(size: 9.5, color: AppColors.text45)),
          if (report.details.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(report.details, style: AppText.body(size: 12.5, color: AppColors.text60)),
          ],
          for (final r in report.replies) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.fillSubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.from.toUpperCase(),
                      style: AppText.mono(size: 9, color: AppColors.accentLink)),
                  const SizedBox(height: 4),
                  Text(r.text, style: AppText.body(size: 12.5)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
