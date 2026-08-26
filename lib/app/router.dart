import 'package:go_router/go_router.dart';

import '../core/backend/reader_backend.dart';
import '../features/collections/collections_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/history/history_screen.dart';
import '../features/settings/appearance_screen.dart';
import '../features/downloads/storage_screen.dart';
import '../features/home/home_screen.dart';
import '../features/kapowarr/kapowarr_settings_screen.dart';
import '../features/kapowarr/kapowarr_status_screen.dart';
import '../features/kapowarr/kapowarr_volume_detail_screen.dart';
import '../features/kapowarr/kapowarr_volumes_screen.dart';
import '../features/library/library_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/reader/reader_screen.dart';
import '../features/search/cross_server_search_screen.dart';
import '../features/series/series_screen.dart';
import '../features/stats/stats_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/servers_screen.dart';
import '../features/settings/server_edit_screen.dart';

GoRouter buildRouter({
  String initialLocation = '/home',
  void Function(String path)? onRouteChange,
}) =>
    GoRouter(
  initialLocation: initialLocation,
  redirect: (context, state) {
    onRouteChange?.call(state.uri.toString());
    return null;
  },
  routes: [
    GoRoute(
        path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
    GoRoute(
      path: '/onboarding/add-server',
      builder: (context, state) => ServerEditScreen(
        initialType: state.extra as ServerType?,
        isOnboarding: true,
      ),
    ),
    GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/search',
      builder: (context, state) => const CrossServerSearchScreen(),
    ),
    GoRoute(
      path: '/library/:id',
      builder: (context, state) =>
          LibraryScreen(libraryId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/series/:id',
      builder: (context, state) =>
          SeriesScreen(seriesId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/read/:bookId',
      builder: (context, state) {
        final pageParam = state.uri.queryParameters['page'];
        return ReaderScreen(
          bookId: state.pathParameters['bookId']!,
          initialPage: pageParam == null ? null : int.tryParse(pageParam),
        );
      },
    ),
    GoRoute(
        path: '/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(
      path: '/settings/appearance',
      builder: (context, state) => const AppearanceScreen(),
    ),
    GoRoute(
      path: '/history',
      builder: (context, state) => const HistoryScreen(),
    ),
    GoRoute(
      path: '/collections',
      builder: (context, state) => const CollectionsScreen(),
    ),
    GoRoute(
      path: '/settings/servers',
      builder: (context, state) => const ServersScreen(),
    ),
    GoRoute(
      path: '/settings/servers/new',
      builder: (context, state) => const ServerEditScreen(),
    ),
    GoRoute(
      path: '/settings/servers/:id/edit',
      builder: (context, state) =>
          ServerEditScreen(serverId: state.pathParameters['id']),
    ),
    GoRoute(
      path: '/settings/kapowarr',
      builder: (context, state) => const KapowarrStatusScreen(),
    ),
    GoRoute(
      path: '/settings/kapowarr/edit',
      builder: (context, state) => const KapowarrSettingsScreen(),
    ),
    GoRoute(
      path: '/settings/kapowarr/volumes',
      builder: (context, state) => const KapowarrVolumesScreen(),
    ),
    GoRoute(
      path: '/settings/kapowarr/volumes/:id',
      builder: (context, state) => KapowarrVolumeDetailScreen(
        volumeId: int.parse(state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/settings/downloads',
      builder: (context, state) => const DownloadsScreen(),
    ),
    GoRoute(
      path: '/settings/storage',
      builder: (context, state) => const StorageScreen(),
    ),
    GoRoute(
      path: '/stats',
      builder: (context, state) => const StatsScreen(),
    ),
  ],
);
