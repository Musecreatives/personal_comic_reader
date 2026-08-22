import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/series/series_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/servers_screen.dart';
import '../features/settings/server_edit_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
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
        path: '/settings', builder: (context, state) => const SettingsScreen()),
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
  ],
);
