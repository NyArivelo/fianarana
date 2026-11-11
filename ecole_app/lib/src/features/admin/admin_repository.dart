import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/security/password_hasher.dart';

class AdminRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  AdminRepository(this.db);

  Stream<List<User>> watchUsers() => (db.select(db.users)..where((t) => t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.asc(t.username)])).watch();
  Stream<List<Role>> watchRoles() => (db.select(db.roles)..where((t) => t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.asc(t.name)])).watch();
  Stream<List<AuditLog>> watchAuditLogs({int limit = 300}) => (db.select(db.auditLogs)..orderBy([(t)=>OrderingTerm.desc(t.timestamp)])..limit(limit)).watch();

  Future<void> createUser({required String username, required String displayName, required String password, String? email, List<String> roleIds = const []}) async {
    final id = _uuid.v4();
    await db.transaction(() async {
      await db.into(db.users).insert(UsersCompanion.insert(id: id, username: username, passwordHash: PasswordHasher.hash(password), displayName: displayName, email: Value(email)));
      for (final rid in roleIds) {
        await db.into(db.userRoles).insert(UserRolesCompanion.insert(userId: id, roleId: rid));
      }
    });
  }

  Future<void> updateUser(User u, {String? displayName, String? email, bool? isActive, List<String>? roleIds}) async {
    await db.transaction(() async {
      await (db.update(db.users)..where((t)=>t.id.equals(u.id))).write(UsersCompanion(
        displayName: displayName != null ? Value(displayName) : const Value.absent(),
        email: email != null ? Value(email) : const Value.absent(),
        isActive: isActive != null ? Value(isActive) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ));
      if (roleIds != null) {
        await (db.delete(db.userRoles)..where((t)=>t.userId.equals(u.id))).go();
        for (final rid in roleIds) {
          await db.into(db.userRoles).insert(UserRolesCompanion.insert(userId: u.id, roleId: rid));
        }
      }
    });
  }

  Future<void> resetPassword(String userId, String newPassword) async {
    await (db.update(db.users)..where((t)=>t.id.equals(userId))).write(UsersCompanion(
      passwordHash: Value(PasswordHasher.hash(newPassword)),
      failedLoginAttempts: const Value(0),
      lockedUntil: const Value(null),
      mustChangePassword: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<List<String>> roleIdsForUser(String userId) async {
    final rows = await (db.select(db.userRoles)..where((t)=>t.userId.equals(userId))).get();
    return rows.map((r)=>r.roleId).toList();
  }

  Future<void> upsertRole({String? id, required String name, String? description, String scope = 'global'}) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.roles).insert(RolesCompanion.insert(id: _uuid.v4(), name: name, description: Value(description), scope: Value(scope)));
    } else {
      await (db.update(db.roles)..where((t)=>t.id.equals(id))).write(RolesCompanion(name: Value(name), description: Value(description), scope: Value(scope), updatedAt: Value(now)));
    }
  }

  Future<void> ensureDefaultRoles() async {
    final existing = await db.select(db.roles).get();
    if (existing.isNotEmpty) {
      // ensure admin role has global scope
      final admin = existing.where((r)=>r.name=='Administrateur').firstOrNull;
      if (admin != null && admin.scope != 'global') {
        await (db.update(db.roles)..where((t)=>t.id.equals(admin.id))).write(const RolesCompanion(scope: Value('global')));
      }
      return;
    }
    // if roles missing (shouldn't happen after bootstrap) seed basics
    final defaults = [
      ('Administrateur','Accès complet','global',true),
      ('Direction','Direction de l\'établissement','global',true),
      ('Secrétariat','Gestion administrative','global',true),
      ('Économat/Caisse','Gestion financière et caisse','caisse',true),
      ('Enseignant','Accès pédagogique restreint','restricted',true),
    ];
    for (final d in defaults) {
      await db.into(db.roles).insert(RolesCompanion.insert(id: _uuid.v4(), name: d.$1, description: Value(d.$2), scope: Value(d.$3), isSystem: Value(d.$4)));
    }
  }

  /// Export audit logs as JSON string and its SHA-256 hash.
  Future<({String json, String sha256})> exportAuditLogs({DateTime? from, DateTime? to}) async {
    final q = db.select(db.auditLogs)..orderBy([(t)=>OrderingTerm.asc(t.timestamp)]);
    if (from != null) q.where((t)=>t.timestamp.isBiggerOrEqualValue(from.toUtc()));
    if (to != null) q.where((t)=>t.timestamp.isSmallerOrEqualValue(to.toUtc()));
    final rows = await q.get();
    final list = rows.map((r)=>({
      'id': r.id, 'timestamp': r.timestamp.toIso8601String(), 'userId': r.userId, 'username': r.username,
      'module': r.module, 'action': r.action, 'targetType': r.targetType, 'targetId': r.targetId,
      'details': r.details, 'result': r.result,
    })).toList();
    final jsonStr = const JsonEncoder.withIndent('  ').convert({'exportedAt': DateTime.now().toUtc().toIso8601String(), 'count': list.length, 'logs': list});
    final hash = sha256.convert(utf8.encode(jsonStr)).toString();
    return (json: jsonStr, sha256: hash);
  }
}
