import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/core/security/permission_service.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';

final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService(ref.watch(appDatabaseProvider));
});

/// Ensemble des permissions effectives de l'utilisateur connecté (admin => toutes).
final currentPermissionsProvider = FutureProvider<Set<String>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  final userId = auth.userId;
  if (!auth.isAuthenticated || userId == null || userId.isEmpty) {
    return <String>{};
  }
  final svc = ref.watch(permissionServiceProvider);
  return svc.permissionsOf(userId);
});

final hasPermissionProvider = Provider.family<bool, String>((ref, permissionCode) {
  final perms = ref.watch(currentPermissionsProvider).valueOrNull;
  if (perms == null) return false;
  return perms.contains(permissionCode);
});

/// Vrai si au moins une des permissions demandées est accordée.
final hasAnyPermissionProvider = Provider.family<bool, List<String>>((ref, codes) {
  final perms = ref.watch(currentPermissionsProvider).valueOrNull;
  if (perms == null) return false;
  for (final c in codes) {
    if (perms.contains(c)) return true;
  }
  return false;
});

/// Permission de lecture requise pour accéder à un module/route.
String? requiredPermissionForRoute(String location) {
  String loc = location;
  if (loc.isEmpty) loc = '/';
  // Normaliser (sans query)
  final q = loc.indexOf('?');
  if (q >= 0) loc = loc.substring(0, q);
  if (loc == '/' || loc == '/bootstrap' || loc == '/setup' || loc == '/login') return null;
  if (loc.startsWith('/students')) return 'students.read';
  if (loc.startsWith('/attendance')) return 'attendance.read';
  if (loc.startsWith('/grades')) return 'grades.read';
  if (loc.startsWith('/finance')) return 'finance.read';
  if (loc.startsWith('/timetable')) return 'timetable.read';
  if (loc.startsWith('/calendar')) return 'calendar.read';
  if (loc.startsWith('/staff')) return 'staff.read';
  if (loc.startsWith('/library')) return 'library.read';
  if (loc.startsWith('/facilities')) return 'facilities.read';
  if (loc.startsWith('/documents')) return 'documents.read';
  if (loc == '/settings/users') return 'users.read';
  if (loc.startsWith('/settings')) return 'settings.read';
  return null;
}
