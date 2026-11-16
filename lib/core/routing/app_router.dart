import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/auth/presentation/login_screen.dart';
import 'package:fianarana/features/dashboard/presentation/dashboard_screen.dart';
import 'package:fianarana/features/setup/presentation/bootstrap_screen.dart';
import 'package:fianarana/features/setup/presentation/setup_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);
  return GoRouter(
    initialLocation: '/bootstrap',
    redirect: (context, state) {
      final loggedIn = authState.isAuthenticated;
      final loc = state.matchedLocation;
      final inBootstrap = loc == '/bootstrap';
      final inSetup = loc == '/setup';
      final loggingIn = loc == '/login';

      // Bootstrap/setup gèrent eux-mêmes leur flux initial
      if (inBootstrap || inSetup) return null;

      if (!loggedIn && !loggingIn) return '/login';
      if (loggedIn && loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/bootstrap',
        builder: (context, state) => const BootstrapScreen(),
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
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page introuvable: ${state.uri}')),
    ),
  );
});
