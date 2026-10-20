import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/motion.dart';
import '../../core/comicvine/comicvine_client.dart';
import '../shared/series_cover.dart';

/// Searches ComicVine volumes for [query] (editable in the sheet) and lets
/// the user pick one. Returns the picked volume with its full details
/// (summary, credits), or null if dismissed. Nothing is saved here.
Future<ComicVineVolume?> showComicVineMatchSheet(
  BuildContext context, {
  required ComicVineClient client,
  required String query,
}) {
  return showModalBottomSheet<ComicVineVolume>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: Motion.sheetStyle,
    backgroundColor: AppColors.card,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _MatchSheet(client: client, query: query),
  );
}

class _MatchSheet extends StatefulWidget {
  final ComicVineClient client;
  final String query;
  const _MatchSheet({required this.client, required this.query});

  @override
  State<_MatchSheet> createState() => _MatchSheetState();
}

class _MatchSheetState extends State<_MatchSheet> {
  late final _query = TextEditingController(text: widget.query);
  List<ComicVineVolume>? _results;
  String? _error;
  bool _searching = false;
  int? _loadingId;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.client.searchVolumes(q);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pick(ComicVineVolume v) async {
    setState(() {
      _loadingId = v.id;
      _error = null;
    });
    try {
      final full = await widget.client.volume(v.id);
      if (mounted) Navigator.pop(context, full);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingId = null;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Find on ComicVine', style: AppText.heading(size: 18)),
          const SizedBox(height: 14),
          TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            style: AppText.body(size: 14),
            decoration: InputDecoration(
              hintText: 'Series title',
              filled: true,
              fillColor: AppColors.fillSubtle,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search, size: 20),
                onPressed: _searching ? null : _search,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: AppText.body(size: 12.5, color: AppColors.dangerText),
              ),
            ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (results != null && results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No ComicVine volumes match "${_query.text.trim()}". '
                'Try a shorter title.',
                style: AppText.body(size: 12.5, color: AppColors.text45),
              ),
            )
          else if (results != null)
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (context, i) => _MatchRow(
                  volume: results[i],
                  loading: _loadingId == results[i].id,
                  onTap: _loadingId == null ? () => _pick(results[i]) : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  final ComicVineVolume volume;
  final bool loading;
  final VoidCallback? onTap;
  const _MatchRow({required this.volume, required this.loading, this.onTap});

  @override
  Widget build(BuildContext context) {
    final meta = [
      ?volume.startYear,
      ?volume.publisher,
      if (volume.issueCount > 0) '${volume.issueCount} issues',
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 64,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SeriesCover(imageUrl: volume.thumbUrl),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    volume.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 14, weight: FontWeight.w600),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      style: AppText.body(size: 12, color: AppColors.text45),
                    ),
                  ],
                ],
              ),
            ),
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}
