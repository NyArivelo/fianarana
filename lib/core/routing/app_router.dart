import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/auth/presentation/login_screen.dart';
import 'package:fianarana/features/dashboard/presentation/dashboard_screen.dart';
import 'package:fianarana/features/setup/presentation/bootstrap_screen.dart';
import 'package:fianarana/features/setup/presentation/setup_screen.dart';
import 'package:fianarana/features/attendance/presentation/attendance_screen.dart';
import 'package:fianarana/features/facilities/presentation/facilities_screen.dart';
import 'package:fianarana/features/finance/presentation/finance_screen.dart';
import 'package:fianarana/features/finance/presentation/schedules_screen.dart';
import 'package:fianarana/features/grades/presentation/councils_screen.dart';
import 'package:fianarana/features/grades/presentation/grades_screen.dart';
import 'package:fianarana/features/library/presentation/library_screen.dart';
import 'package:fianarana/features/settings/presentation/settings_screen.dart';
import 'package:fianarana/features/staff/presentation/staff_screen.dart';
import 'package:fianarana/features/students/presentation/student_detail_screen.dart';
import 'package:fianarana/features/students/presentation/students_screen.dart';
import 'package:fianarana/features/timetable/presentation/timetable_screen.dart';

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
      GoRoute(
        path: '/students',
        builder: (context, state) => const StudentsScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const StudentDetailScreen(studentId: 'new'),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) => StudentDetailScreen(studentId: state.pathParameters['id']),
          ),
        ],
      ),
      GoRoute(
        path: '/attendance',
        builder: (context, state) => const AttendanceScreen(),
      ),
      GoRoute(
        path: '/finance',
        builder: (context, state) => const FinanceScreen(),
        routes: [
          GoRoute(path: 'schedules', builder: (context, state) => const SchedulesScreen()),
        ],
      ),
      GoRoute(
        path: '/grades',
        builder: (context, state) => const GradesScreen(),
        routes: [
          GoRoute(path: 'councils', builder: (context, state) => const CouncilsScreen()),
        ],
      ),
      GoRoute(
        path: '/timetable',
        builder: (context, state) => const TimetableScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(path: '/staff', builder: (context, state) => const StaffScreen()),
      GoRoute(path: '/library', builder: (context, state) => const LibraryScreen()),
      GoRoute(path: '/facilities', builder: (context, state) => const FacilitiesScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page introuvable: ${state.uri}')),
    ),
  );
});
