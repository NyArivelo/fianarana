import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fianarana/core/security/permission_providers.dart';
import 'package:fianarana/core/workspace/app_shell.dart';
import 'package:fianarana/features/attendance/presentation/attendance_screen.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/auth/presentation/login_screen.dart';
import 'package:fianarana/features/calendar/presentation/calendar_screen.dart';
import 'package:fianarana/features/dashboard/presentation/dashboard_screen.dart';
import 'package:fianarana/features/admin/presentation/users_admin_screen.dart';
import 'package:fianarana/features/discipline/presentation/discipline_screen.dart';
import 'package:fianarana/features/documents/presentation/document_studio_screen.dart';
import 'package:fianarana/features/facilities/presentation/facilities_screen.dart';
import 'package:fianarana/features/facilities/presentation/facility_operations_screen.dart';
import 'package:fianarana/features/finance/presentation/fee_catalog_screen.dart';
import 'package:fianarana/features/finance/presentation/finance_screen.dart';
import 'package:fianarana/features/finance/presentation/schedules_screen.dart';
import 'package:fianarana/features/grades/presentation/councils_screen.dart';
import 'package:fianarana/features/grades/presentation/grades_screen.dart';
import 'package:fianarana/features/library/presentation/library_screen.dart';
import 'package:fianarana/features/settings/presentation/settings_screen.dart';
import 'package:fianarana/features/settings/presentation/structure_settings_screen.dart';
import 'package:fianarana/features/setup/presentation/bootstrap_screen.dart';
import 'package:fianarana/features/setup/presentation/setup_screen.dart';
import 'package:fianarana/features/staff/presentation/staff_screen.dart';
import 'package:fianarana/features/students/presentation/student_detail_screen.dart';
import 'package:fianarana/features/students/presentation/students_screen.dart';
import 'package:fianarana/features/timetable/presentation/timetable_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);
  final permsAsync = ref.watch(currentPermissionsProvider);
  final perms = permsAsync.valueOrNull;
  final permsLoaded = permsAsync.hasValue;

  return GoRouter(
    initialLocation: '/bootstrap',
    redirect: (context, state) {
      final loggedIn = authState.isAuthenticated;
      final loc = state.matchedLocation;
      final inBootstrap = loc == '/bootstrap';
      final inSetup = loc == '/setup';
      final loggingIn = loc == '/login';

      if (inBootstrap || inSetup) return null;

      if (!loggedIn && !loggingIn) return '/login';
      if (loggedIn && loggingIn) return '/';

      // RBAC bloquant au niveau navigation (si permissions chargées)
      if (loggedIn && permsLoaded) {
        final required = requiredPermissionForRoute(loc);
        if (required != null && !(perms?.contains(required) ?? false)) {
          return '/';
        }
      }
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
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
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
            path: '/discipline',
            builder: (context, state) => const DisciplineScreen(),
          ),
          GoRoute(
            path: '/finance',
            builder: (context, state) => const FinanceScreen(),
            routes: [
              GoRoute(path: 'schedules', builder: (context, state) => const SchedulesScreen()),
              GoRoute(path: 'fees', builder: (context, state) => const FeeCatalogScreen()),
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
            builder: (context, state) => TimetableScreen(
              initialClassId: state.uri.queryParameters['class'],
              initialTeacherId: state.uri.queryParameters['teacher'],
            ),
          ),
          GoRoute(
            path: '/calendar',
            builder: (context, state) => const CalendarScreen(),
          ),
          GoRoute(
            path: '/documents',
            builder: (context, state) => const DocumentStudioScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
            routes: [
              GoRoute(path: 'users', builder: (context, state) => const UsersAdminScreen()),
              GoRoute(path: 'structure', builder: (context, state) => const StructureSettingsScreen()),
            ],
          ),
          GoRoute(path: '/staff', builder: (context, state) => const StaffScreen()),
          GoRoute(path: '/library', builder: (context, state) => const LibraryScreen()),
          GoRoute(
            path: '/facilities',
            builder: (context, state) => const FacilitiesScreen(),
            routes: [
              GoRoute(path: 'operations', builder: (context, state) => const FacilityOperationsScreen()),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page introuvable: ${state.uri}')),
    ),
  );
});
