import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/admin/admin_providers.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/settings/settings_providers.dart';

final currentUserScopeProvider = FutureProvider<({String scope, List<String>? allowedClassIds})>((ref) async {
  final user = ref.watch(authControllerProvider).currentUser;
  if (user == null) return (scope: 'none', allowedClassIds: <String>[]);
  final authz = ref.watch(authorizationServiceProvider);
  final scope = await authz.effectiveScope(user.id);
  if (scope == 'restricted') {
    final years = ref.watch(academicYearsProvider).valueOrNull ?? [];
    final yearId = years.where((y) => y.isCurrent).firstOrNull?.id ?? (years.isNotEmpty ? years.first.id : null);
    final ids = await authz.assignedClassIds(user.id, academicYearId: yearId);
    return (scope: scope, allowedClassIds: ids);
  }
  return (scope: scope, allowedClassIds: null); // null = all
});
