import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'src/core/services/app_preferences.dart';
import 'src/core/services/auto_backup_service.dart';
import 'src/core/services/backup_service.dart';
import 'src/features/auth/auth_controller.dart';
import 'src/features/auth/login_screen.dart';
import 'src/features/dashboard/dashboard_screen.dart';
import 'src/features/setup/setup_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: EcoleApp()));
}

class EcoleApp extends ConsumerStatefulWidget {
  const EcoleApp({super.key});

  @override
  ConsumerState<EcoleApp> createState() => _EcoleAppState();
}

class _EcoleAppState extends ConsumerState<EcoleApp> with WidgetsBindingObserver {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      await ref.read(appPreferencesProvider).load();
      await ref.read(authControllerProvider.notifier).initialize();
      // Best-effort automatic backup on startup
      try {
        await AutoBackupService(BackupService()).maybeRunAutoBackup();
      } catch (_) {}
    });

    _router = GoRouter(
      initialLocation: '/splash',
      refreshListenable: _AuthRefresh(ref),
      redirect: (context, state) {
        final auth = ref.read(authControllerProvider);
        final loc = state.matchedLocation;

        if (!auth.initialized) {
          return loc == '/splash' ? null : '/splash';
        }
        if (auth.needsSetup) {
          return loc == '/setup' ? null : '/setup';
        }
        if (auth.currentUser == null) {
          return loc == '/login' ? null : '/login';
        }
        if (loc == '/login' || loc == '/setup' || loc == '/splash') {
          return '/';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/splash',
          builder: (context, state) => const _SplashScreen(),
        ),
        GoRoute(
          path: '/setup',
          builder: (context, state) => const SetupScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardScreen(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached || state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // Best-effort automatic backup on close/background
      AutoBackupService(BackupService()).maybeRunAutoBackup().catchError((_) => null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(appPreferencesProvider);
    return MaterialApp.router(
      title: 'Gestion Scolaire',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E5AA8)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E5AA8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(prefs.uiScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      routerConfig: _router,
    );
  }
}

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this.ref) {
    ref.listen<AuthState>(authControllerProvider, (prev, next) => notifyListeners());
  }
  final WidgetRef ref;
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Chargement de l\'application...'),
          ],
        ),
      ),
    );
  }
}
