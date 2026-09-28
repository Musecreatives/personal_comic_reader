import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../backends/suwayomi/suwayomi_backend.dart';
import '../search/acquire_search.dart';
import '../search/source_showcase.dart';
import '../shared/back_button.dart';
import '../shared/error_state.dart';

/// Browse Suwayomi's sources directly (5g): a Popular/Latest shelf per
/// source, a source's full listing when picked, and a search within it.
/// Tapping a title opens its review sheet, where it can be added.
class SourceBrowseScreen extends ConsumerStatefulWidget {
  const SourceBrowseScreen({super.key});

  @override
  ConsumerState<SourceBrowseScreen> createState() => _SourceBrowseScreenState();
}

class _SourceBrowseScreenState extends ConsumerState<SourceBrowseScreen> {
  Future<List<SourceInfo>>? _sourcesFuture;
  SourceListingCache? _listings;
  SourceInfo? _selected;
  final _searchController = TextEditingController();
  String _query = '';
  Timer? _debounce;
  Future<SourcePage>? _resultsFuture;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _select(SourceInfo? source) {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _selected = source;
      _query = '';
      _resultsFuture = null;
    });
  }

  void _onSearchChanged(SuwayomiBackend backend, String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final source = _selected;
      if (!mounted || source == null) return;
      setState(() {
        _query = value.trim();
        _resultsFuture = _query.isEmpty
            ? null
            : backend.browseSource(source.id, query: _query);
      });
    });
  }

  void _open(SuwayomiBackend backend, SourceInfo source, SourceManga m) =>
      showMangaPreview(
        context,
        ref,
        backend: backend,
        id: m.id,
        title: m.title,
        coverUrl: m.thumbnailUrl,
        sourceName: source.name,
      );

  @override
  Widget build(BuildContext context) {
    final backendAsync = ref.watch(activeBackendProvider);

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Row(
                children: [
                  // From a source's listing, back goes to the shelves first.
                  AppBackButton(
                      onTap: _selected == null
                          ? null
                          : () => _select(null)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_selected?.name ?? 'Browse sources',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.largeTitle(size: 22)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: backendAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => AppErrorState(
                    error: e, onRetry: () => ref.invalidate(activeBackendProvider)),
                data: (backend) {
                  if (backend is! SuwayomiBackend) {
                    return Center(
                      child: Text('Switch to a Suwayomi server to browse sources.',
                          style: AppText.body(color: AppColors.text45)),
                    );
                  }
                  _sourcesFuture ??= backend.listInstalledSources();
                  final listings = _listings ??= SourceListingCache(backend);
                  final source = _selected;
                  if (source == null) {
                    return FutureBuilder<List<SourceInfo>>(
                      future: _sourcesFuture,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return AppErrorState(error: snap.error!);
                        }
                        final all = snap.data;
                        if (all == null) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        bool main(SourceInfo s) => s.lang == 'en' || s.lang == 'all';
                        return SourceShelves(
                          // English/multi-language first: 100+ translated
                          // copies of one site would bury the rest.
                          sources: [...all.where(main), ...all.where((s) => !main(s))],
                          cache: listings,
                          onOpen: (s, m) => _open(backend, s, m),
                          onSeeAll: _select,
                        );
                      },
                    );
                  }
                  return Column(
                    children: [
                      _SearchField(
                        controller: _searchController,
                        hint: 'Search ${source.name}',
                        onChanged: (v) => _onSearchChanged(backend, v),
                      ),
                      Expanded(
                        child: _resultsFuture == null
                            ? SourceCatalogGrid(
                                key: ValueKey(source.id),
                                source: source,
                                cache: listings,
                                onOpen: (m) => _open(backend, source, m),
                              )
                            : _SearchResults(
                                future: _resultsFuture!,
                                onOpen: (m) => _open(backend, source, m),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.fillSubtle,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 16, color: AppColors.text45),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: AppText.body(size: 14),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: AppText.body(size: 14, color: AppColors.text45),
                  isDense: true,
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final Future<SourcePage> future;
  final ValueChanged<SourceManga> onOpen;
  const _SearchResults({required this.future, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SourcePage>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return AppErrorState(error: snapshot.error!);
        final mangas = snapshot.data?.mangas;
        if (mangas == null) return const Center(child: CircularProgressIndicator());
        if (mangas.isEmpty) {
          return Center(
              child: Text('No results.', style: AppText.body(color: AppColors.text45)));
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140,
            childAspectRatio: 0.56,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
          ),
          itemCount: mangas.length,
          itemBuilder: (context, i) =>
              SourceMangaCard(manga: mangas[i], onTap: () => onOpen(mangas[i])),
        );
      },
    );
  }
}
