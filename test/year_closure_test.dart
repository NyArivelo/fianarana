import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/services/year_closure_service.dart';

/// Clôture annuelle : archive JSON scellée, empreinte SHA-256 et passage de
/// l'année scolaire au statut « Clôturée ».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory archiveDir;
  late YearClosureService service;
  const yearId = 'year-cloture-1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.establishments).insert(EstablishmentsCompanion.insert(
          id: const Value('etab-1'),
          code: 'ETAB-TEST',
          name: 'Établissement de test',
        ));
    await db.into(db.schoolYears).insert(SchoolYearsCompanion.insert(
          id: const Value(yearId),
          establishmentId: 'etab-1',
          code: '2025-2026',
          label: 'Année 2025-2026',
          startDate: DateTime(2025, 9, 1),
          endDate: DateTime(2026, 6, 30),
        ));
    archiveDir = Directory.systemTemp.createTempSync('fianarana_closure_test');
    service = YearClosureService(db, archiveDirOverride: archiveDir);
  });

  tearDown(() async {
    await db.close();
    if (archiveDir.existsSync()) archiveDir.deleteSync(recursive: true);
  });

  test('scelle une archive JSON avec empreinte et clôt l\'année', () async {
    final file = await service.closeSchoolYear(
      schoolYearId: yearId,
      actorUsername: 'admin',
    );

    expect(file.existsSync(), isTrue);
    expect(p.isWithin(archiveDir.path, file.path), isTrue);
    expect(p.basename(file.path), startsWith('cloture_2025-2026_'));
    expect(file.path, endsWith('.json'));

    final bytes = file.readAsBytesSync();
    final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(payload['sealedReadOnly'], isTrue);
    expect((payload['schoolYear'] as Map)['id'], yearId);
    expect((payload['schoolYear'] as Map)['label'], 'Année 2025-2026');
    expect((payload['counts'] as Map)['students'], 0);
    expect(payload['periods'], isEmpty);

    final hashFile = File('${file.path}.sha256');
    expect(hashFile.existsSync(), isTrue);
    final hash = hashFile.readAsStringSync().trim().split(RegExp(r'\s+')).first;
    expect(hash, sha256Of(bytes));
    expect(hashFile.readAsStringSync(), contains(p.basename(file.path)));

    final closures = await service.listClosures();
    expect(closures, hasLength(1));
    expect(closures.first.schoolYearId, yearId);
    expect(closures.first.archivePath, file.path);
    expect(closures.first.archiveHash, hash);
    expect(closures.first.status, contains('Clôturée'));
    expect(closures.first.summaryJson, isNotNull);

    final year = await (db.select(db.schoolYears)..where((t) => t.id.equals(yearId))).getSingle();
    expect(year.status, 'Clôturée');

    final audits = await (db.select(db.auditLogs)..where((t) => t.module.equals('Année scolaire'))).get();
    expect(audits, isNotEmpty);
    expect(audits.first.description, contains('Clôture annuelle'));
  });

  test('refuse une année scolaire inconnue', () async {
    expect(
      () => service.closeSchoolYear(schoolYearId: 'inconnue'),
      throwsA(isA<StateError>()),
    );
    expect(archiveDir.listSync(), isEmpty);
  });
}

/// Empreinte SHA-256 d'un contenu binaire (format identique au fichier .sha256).
String sha256Of(List<int> bytes) {
  return sha256.convert(bytes).toString();
}
