import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_tokens.dart';
import '../../app/providers.dart';
import '../../core/kapowarr/kapowarr_client.dart';
import '../shared/error_state.dart';

/// Browse every volume Kapowarr tracks (5d, list side). Tapping one opens
/// [KapowarrVolumeDetailScreen] - purely read-only, matching the rest of
/// the Kapowarr integration.
class KapowarrVolumesScreen extends ConsumerStatefulWidget {
  const KapowarrVolumesScreen({super.key});

  @override
  ConsumerState<KapowarrVolumesScreen> createState() => _KapowarrVolumesScreenState();
}

class _KapowarrVolumesScreenState extends ConsumerState<KapowarrVolumesScreen> {
  late Future<List<KapowarrVolume>> _future;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<KapowarrVolume>> _load() async {
    final config = await ref.read(kapowarrConfigStoreProvider).getWithApiKey();
    if (config == null) return [];
    return KapowarrClient(config: config).getVolumes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: Text('Volumes', style: AppText.largeTitle(size: 26)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 38,
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
                        controller: _searchController,
                        onChanged: (v) => setState(() => _search = v.toLowerCase()),
                        style: AppText.body(size: 14),
                        decoration: InputDecoration(
                          hintText: 'Search volumes',
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
            Expanded(
              child: FutureBuilder<List<KapowarrVolume>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return AppErrorState(
                        error: snapshot.error!,
                        onRetry: () => setState(() => _future = _load()));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final volumes = snapshot.data!
                      .where((v) => _search.isEmpty || v.title.toLowerCase().contains(_search))
                      .toList()
                    ..sort((a, b) => a.title.compareTo(b.title));
                  if (volumes.isEmpty) {
                    return Center(
                        child: Text('No volumes found.', style: AppText.body(color: AppColors.text45)));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    itemCount: volumes.length,
                    itemBuilder: (context, i) {
                      final v = volumes[i];
                      return _VolumeRow(
                        volume: v,
                        onTap: () => context.push('/settings/kapowarr/volumes/${v.id}'),
                      );
                    },
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

class _VolumeRow extends StatelessWidget {
  final KapowarrVolume volume;
  final VoidCallback onTap;
  const _VolumeRow({required this.volume, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final progress = volume.issueCount == 0 ? 0.0 : volume.issuesDownloaded / volume.issueCount;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(volume.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(size: 14, weight: FontWeight.w500)),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text('${volume.year} · ${volume.issuesDownloaded}/${volume.issueCount}',
                          style: AppText.mono(size: 9.5)),
                      if (!volume.monitored) ...[
                        const SizedBox(width: 8),
                        Text('UNMONITORED', style: AppText.mono(size: 8.5, color: AppColors.text30)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: AppColors.track,
                      valueColor: AlwaysStoppedAnimation(AppColors.kapowarr),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.text30),
          ],
        ),
      ),
    );
  }
}
