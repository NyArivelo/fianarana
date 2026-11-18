import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/uuid.dart';
import 'package:fianarana/core/security/audit_service.dart';
import 'package:fianarana/core/security/permission_service.dart';

class YearClosureService {
  final AppDatabase db;

  /// Dossier de destination des archives (surchargeable pour les tests).
  final Directory? archiveDirOverride;
  late final AuditService _audit = AuditService(db);
  late final PermissionService _perm = PermissionService(db);
  YearClosureService(this.db, {this.archiveDirOverride});

  Future<void> _require(String? userId) async {
    if (userId == null || userId.isEmpty) return;
    if (!await _perm.userHasPermission(userId, 'settings.update')) {
      throw StateError('Action non autorisée (settings.update)');
    }
  }

  Future<File> closeSchoolYear({
    required String schoolYearId,
    String? actorUserId,
    String? actorUsername,
  }) async {
    await _require(actorUserId);
    final year = await (db.select(db.schoolYears)..where((t) => t.id.equals(schoolYearId))).getSingleOrNull();
    if (year == null) throw StateError('Année scolaire introuvable');

    Future<int> count(String table) async {
      final r = await db.customSelect('SELECT COUNT(*) AS c FROM $table WHERE is_deleted = 0').getSingle();
      return r.read<int>('c');
    }

    final periods = await (db.select(db.periods)..where((t) => t.schoolYearId.equals(schoolYearId))).get();
    final summary = <String, dynamic>{
      'schoolYear': {'id': year.id, 'code': year.code, 'label': year.label, 'start': year.startDate.toIso8601String(), 'end': year.endDate.toIso8601String()},
      'closedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'sealedReadOnly': true,
      'periods': periods.map((p) => {'id': p.id, 'name': p.name, 'isClosed': p.isClosed}).toList(),
      'counts': {
        'students': await count('students'),
        'enrollments': await count('enrollments'),
        'evaluations': await count('evaluations'),
        'payments': await count('payments'),
        'attendance_events': await count('attendance_events'),
      },
      'note': 'Archive de clôture annuelle (coffre-fort légal) - synthèse scellée en lecture seule.',
    };

    final content = const JsonEncoder.withIndent('  ').convert(summary);
    final bytes = utf8.encode(content);
    final hash = sha256.convert(bytes).toString();
    final outDir = archiveDirOverride ??
        Directory(p.join((await getApplicationDocumentsDirectory()).path, 'fianarana_archives'));
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final stamp = DateTime.now();
    final file = File(p.join(outDir.path, 'cloture_${year.code}_${stamp.year}${stamp.month.toString().padLeft(2,'0')}${stamp.day.toString().padLeft(2,'0')}.json'));
    await file.writeAsBytes(bytes);
    final hashFile = File('${file.path}.sha256');
    await hashFile.writeAsString('$hash  ${p.basename(file.path)}\n');

    await db.into(db.yearClosures).insert(YearClosuresCompanion.insert(
      id: Value(newUuid()),
      schoolYearId: schoolYearId,
      closedAt: DateTime.now(),
      closedByUserId: Value(actorUserId),
      archivePath: Value(file.path),
      archiveHash: Value(hash),
      status: const Value('Clôturée (archive scellée)'),
      summaryJson: Value(content),
    ));
    await (db.update(db.schoolYears)..where((t)=>t.id.equals(schoolYearId))).write(const SchoolYearsCompanion(status: Value('Clôturée')));
    await _audit.log(userId: actorUserId, username: actorUsername, module: 'Année scolaire', targetObject: schoolYearId, description: 'Clôture annuelle et archivage légal scellé', result: 'Succès', metadata: {'archive': file.path, 'hash': hash});
    return file;
  }

  Future<List<YearClosure>> listClosures() {
    return (db.select(db.yearClosures)..where((t)=>t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.desc(t.closedAt)])).get();
  }
}
