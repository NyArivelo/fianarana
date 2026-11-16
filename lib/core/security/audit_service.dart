import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';

class AuditService {
  final AppDatabase db;
  AuditService(this.db);

  Future<void> log({
    String? userId,
    String? username,
    required String module,
    String? targetObject,
    required String description,
    String result = 'Succès',
    Map<String, dynamic>? metadata,
  }) async {
    final ts = DateTime.now().toUtc();
    final id = newUuid();
    final payload = jsonEncode({
      'id': id,
      'ts': ts.toIso8601String(),
      'userId': userId,
      'username': username,
      'module': module,
      'target': targetObject,
      'description': description,
      'result': result,
      'meta': metadata,
    });
    final hash = sha256.convert(utf8.encode(payload)).toString();
    await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
      id: id,
      timestampUtc: ts,
      userId: Value(userId),
      username: Value(username),
      module: module,
      targetObject: Value(targetObject),
      description: description,
      result: Value(result),
      hashSha256: Value(hash),
    ));
  }
}
