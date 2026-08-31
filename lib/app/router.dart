import 'package:go_router/go_router.dart';

import '../core/backend/reader_backend.dart';
import '../features/auth/login_screen.dart';
import '../features/collections/collections_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/shared/glass_bottom_nav.dart';
import '../features/suwayomi/suwayomi_maintenance_screen.dart';
import '../features/history/history_screen.dart';
import '../features/settings/appearance_screen.dart';
import '../features/settings/backup_import_screen.dart';
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
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
        path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
    GoRoute(
      path: '/onboarding/add-server',
      builder: (context, state) => ServerEditScreen(
        initialType: state.extra as ServerType?,
        isOnboarding: true,
      ),
    ),
    // The 5 root tabs live inside a StatefulShellRoute so the glass bottom
    // nav bar (GlassNavScaffold) persists across them and each keeps its
    // own navigation stack. Every drill-down page (a series, the reader, a
    // settings detail screen, /library/:id for a specific library) stays a
    // sibling GoRoute outside the shell below, so it renders full-screen
    // without the bar - only these 5 exact roots show it.
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          GlassNavScaffold(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/search',
            builder: (context, state) => const CrossServerSearchScreen(),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/library',
            builder: (context, state) => const LibraryScreen(),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/history', builder: (context, state) => const HistoryScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
        ]),
      ],
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
      path: '/settings/appearance',
      builder: (context, state) => const AppearanceScreen(),
    ),
    GoRoute(
      path: '/settings/import-backup',
      builder: (context, state) => const BackupImportScreen(),
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
      path: '/settings/suwayomi',
      builder: (context, state) => const SuwayomiMaintenanceScreen(),
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
