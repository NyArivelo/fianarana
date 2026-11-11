import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../core/security/authorization_service.dart';
import 'admin_repository.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) => AdminRepository(ref.watch(appDatabaseProvider)));
final authorizationServiceProvider = Provider<AuthorizationService>((ref) => AuthorizationService(ref.watch(appDatabaseProvider)));

final adminUsersProvider = StreamProvider<List<User>>((ref) => ref.watch(adminRepositoryProvider).watchUsers());
final adminRolesProvider = StreamProvider<List<Role>>((ref) => ref.watch(adminRepositoryProvider).watchRoles());
final auditLogsProvider = StreamProvider<List<AuditLog>>((ref) => ref.watch(adminRepositoryProvider).watchAuditLogs());
