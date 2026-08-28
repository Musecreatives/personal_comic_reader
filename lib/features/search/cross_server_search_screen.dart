import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/backend/models.dart';
import '../../core/backend/reader_backend.dart';
import '../shared/back_button.dart';
import '../shared/error_state.dart';
import '../shared/series_cover.dart';

/// One query, searched against every configured server's own library at
/// once (5c), results grouped per server. This searches what's already in
/// each server's library - it does not reach into Suwayomi's external
/// source catalog, which is a different, source-scoped kind of search.
class CrossServerSearchScreen extends ConsumerStatefulWidget {
  const CrossServerSearchScreen({super.key});

  @override
  ConsumerState<CrossServerSearchScreen> createState() => _CrossServerSearchScreenState();
}

class _CrossServerSearchScreenState extends ConsumerState<CrossServerSearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final backendsAsync = ref.watch(allBackendsProvider);

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 12),
                  Text('Search', style: AppText.largeTitle()),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: AppColors.fillSubtle,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: AppColors.borderStrong),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 16, color: AppColors.text60),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        onChanged: _onChanged,
                        autofocus: true,
                        style: AppText.body(size: 15),
                        decoration: InputDecoration(
                          hintText: 'Search across every server',
                          hintStyle: AppText.body(size: 15, color: AppColors.text45),
                          isDense: true,
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _query.isEmpty
                  ? Center(
                      child: Text('Type to search your libraries.',
                          style: AppText.body(color: AppColors.text45)),
                    )
                  : backendsAsync.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, st) => AppErrorState(error: e),
                      data: (backends) {
                        if (backends.isEmpty) {
                          return Center(
                              child: Text('No servers configured.',
                                  style: AppText.body(color: AppColors.text45)));
                        }
                        return _ResultsList(backends: backends, query: _query);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  final List<ReaderBackend> backends;
  final String query;
  const _ResultsList({required this.backends, required this.query});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<(ReaderBackend, List<Series>)>>(
      future: Future.wait(backends.map((b) async {
        try {
          final result = await b.listSeries(search: query, size: 10);
          return (b, result.items);
        } catch (_) {
          return (b, const <Series>[]);
        }
      })),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final groups = snapshot.data!.where((g) => g.$2.isNotEmpty).toList();
        if (groups.isEmpty) {
          return Center(
              child: Text('No matches on any server.', style: AppText.body(color: AppColors.text45)));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            for (final (backend, series) in groups) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: AppColors.sourceColor(backend.config.type.name),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(backend.config.name, style: AppText.body(size: 14, weight: FontWeight.w600)),
                      ],
                    ),
                    Text('${series.length} HITS', style: AppText.mono(size: 10)),
                  ],
                ),
              ),
              for (final s in series)
                _ResultRow(
                  series: s,
                  headers: backend.imageHeaders,
                  onTap: () => context.push('/series/${Uri.encodeComponent(s.id)}'),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _ResultRow extends StatelessWidget {
  final Series series;
  final Map<String, String> headers;
  final VoidCallback onTap;
  const _ResultRow({required this.series, required this.headers, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              height: 60,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SeriesCover(imageUrl: series.thumbnailUrl, headers: headers),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(series.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(size: 14.5, weight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('${series.booksCount} VOL', style: AppText.mono(size: 10.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
