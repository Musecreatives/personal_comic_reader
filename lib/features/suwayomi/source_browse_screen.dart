import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../backends/suwayomi/suwayomi_backend.dart';
import '../../core/backend/reader_backend.dart';
import '../shared/back_button.dart';
import '../shared/error_state.dart';
import '../shared/series_cover.dart';

/// Browse a Suwayomi source's catalog directly (5g) - popular titles by
/// default, searchable, with an "Add to library" action per result. Reuses
/// the same source-search/add-to-library plumbing built for backup import
/// (`SuwayomiBackend.searchSourceCatalog`/`addToLibraryWithCategories`),
/// generalized into `browseSource` for open-ended discovery rather than
/// just matching a known title.
class SourceBrowseScreen extends ConsumerStatefulWidget {
  const SourceBrowseScreen({super.key});

  @override
  ConsumerState<SourceBrowseScreen> createState() => _SourceBrowseScreenState();
}

class _SourceBrowseScreenState extends ConsumerState<SourceBrowseScreen> {
  Future<List<({String id, String name, String lang})>>? _sourcesFuture;
  String? _selectedSourceId;
  String _selectedSourceName = '';
  final _searchController = TextEditingController();
  String _query = '';
  Timer? _debounce;

  Future<({List<({int id, String title, String thumbnailUrl})> mangas, bool hasNext})>?
      _resultsFuture;
  final Set<int> _adding = {};
  final Set<int> _added = {};

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _selectSource(SuwayomiBackend backend, String id, String name) {
    setState(() {
      _selectedSourceId = id;
      _selectedSourceName = name;
      _resultsFuture = backend.browseSource(id);
    });
  }

  void _onSearchChanged(SuwayomiBackend backend, String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || _selectedSourceId == null) return;
      setState(() {
        _query = value.trim();
        _resultsFuture = backend.browseSource(_selectedSourceId!, query: _query);
      });
    });
  }

  Future<void> _addToLibrary(SuwayomiBackend backend, int mangaId) async {
    setState(() => _adding.add(mangaId));
    try {
      await backend.addToLibraryWithCategories(mangaId, const []);
      if (mounted) setState(() => _added.add(mangaId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Couldn't add: $e")));
      }
    } finally {
      if (mounted) setState(() => _adding.remove(mangaId));
    }
  }

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
                  const AppBackButton(),
                  const SizedBox(width: 12),
                  Text(_selectedSourceId == null ? 'Browse sources' : _selectedSourceName,
                      style: AppText.largeTitle(size: 22)),
                ],
              ),
            ),
            Expanded(
              child: backendAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) =>
                    AppErrorState(error: e, onRetry: () => ref.invalidate(activeBackendProvider)),
                data: (backend) {
                  if (backend is! SuwayomiBackend) {
                    return Center(
                      child: Text('Switch to a Suwayomi server to browse sources.',
                          style: AppText.body(color: AppColors.text45)),
                    );
                  }
                  _sourcesFuture ??= backend.listInstalledSources();
                  if (_selectedSourceId == null) {
                    return _SourceList(
                      future: _sourcesFuture!,
                      onSelect: (id, name) => _selectSource(backend, id, name),
                    );
                  }
                  return _ResultsGrid(
                    future: _resultsFuture!,
                    searchController: _searchController,
                    onSearchChanged: (v) => _onSearchChanged(backend, v),
                    backend: backend,
                    adding: _adding,
                    added: _added,
                    onAdd: (id) => _addToLibrary(backend, id),
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

class _SourceList extends StatelessWidget {
  final Future<List<({String id, String name, String lang})>> future;
  final void Function(String id, String name) onSelect;
  const _SourceList({required this.future, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<({String id, String name, String lang})>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(error: snapshot.error!);
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final sources = snapshot.data!;
        if (sources.isEmpty) {
          return Center(
              child: Text('No sources installed - add extensions in Suwayomi maintenance first.',
                  textAlign: TextAlign.center,
                  style: AppText.body(color: AppColors.text45)));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          itemCount: sources.length,
          itemBuilder: (context, i) {
            final s = sources[i];
            return ListTile(
              title: Text(s.name, style: AppText.body(size: 14.5, weight: FontWeight.w500)),
              subtitle: Text(s.lang.toUpperCase(), style: AppText.mono(size: 9.5)),
              trailing: Icon(Icons.chevron_right, size: 18, color: AppColors.text30),
              onTap: () => onSelect(s.id, s.name),
            );
          },
        );
      },
    );
  }
}

class _ResultsGrid extends StatelessWidget {
  final Future<({List<({int id, String title, String thumbnailUrl})> mangas, bool hasNext})> future;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ReaderBackend backend;
  final Set<int> adding;
  final Set<int> added;
  final void Function(int id) onAdd;

  const _ResultsGrid({
    required this.future,
    required this.searchController,
    required this.onSearchChanged,
    required this.backend,
    required this.adding,
    required this.added,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
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
                    controller: searchController,
                    onChanged: onSearchChanged,
                    style: AppText.body(size: 14),
                    decoration: InputDecoration(
                      hintText: 'Search this source',
                      hintStyle: AppText.body(size: 14, color: AppColors.text45),
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: FutureBuilder<({List<({int id, String title, String thumbnailUrl})> mangas, bool hasNext})>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return AppErrorState(error: snapshot.error!);
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final mangas = snapshot.data!.mangas;
              if (mangas.isEmpty) {
                return Center(
                    child: Text('No results.', style: AppText.body(color: AppColors.text45)));
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.6,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                ),
                itemCount: mangas.length,
                itemBuilder: (context, i) {
                  final m = mangas[i];
                  final isAdding = adding.contains(m.id);
                  final isAdded = added.contains(m.id);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SeriesCover(
                                    imageUrl: m.thumbnailUrl, headers: backend.imageHeaders),
                              ),
                            ),
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: Material(
                                color: isAdded ? AppColors.suwayomi : AppColors.accent,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: isAdding || isAdded ? null : () => onAdd(m.id),
                                  child: SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: isAdding
                                        ? const Padding(
                                            padding: EdgeInsets.all(6),
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2, color: Colors.white),
                                          )
                                        : Icon(isAdded ? Icons.check : Icons.add,
                                            size: 16, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(m.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(size: 11.5, weight: FontWeight.w500)),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
