import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/storage/server_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  final serverStore = ServerStore();
  await serverStore.init();

  runApp(
    ProviderScope(
      overrides: [
        serverStoreProvider.overrideWithValue(serverStore),
      ],
      child: const ShaddaiReaderApp(),
    ),
  );
}

class ShaddaiReaderApp extends StatelessWidget {
  const ShaddaiReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Shaddai Reader',
      theme: buildAppTheme(),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
