import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/services/backup_service.dart';

/// Sauvegarde et restauration locales : archive ZIP, manifeste, somme de
/// contrôle et restitution de la base active.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory dataDir;
  late BackupService service;

  File dbFile([String name = 'fianarana.sqlite']) => File(p.join(dataDir.path, name));

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // Force l'ouverture et les migrations de la base de test.
    await db.customSelect('SELECT 1').get();
    dataDir = Directory.systemTemp.createTempSync('fianarana_backup_test');
    service = BackupService(db, dataDirOverride: dataDir);
  });

  tearDown(() async {
    await db.close();
    if (dataDir.existsSync()) {
      dataDir.deleteSync(recursive: true);
    }
  });

  test('crée une archive avec manifeste, médias et somme de contrôle', () async {
    dbFile().writeAsStringSync('base-v1');
    final media = Directory(p.join(dataDir.path, 'media'))..createSync(recursive: true);
    File(p.join(media.path, 'logo.txt')).writeAsStringSync('média');

    final zip = await service.createBackup(type: 'manuel');

    expect(zip.existsSync(), isTrue);
    expect(p.basename(zip.path).startsWith('backup_'), isTrue);

    final records = await service.listBackups();
    expect(records, hasLength(1));
    final record = records.first;
    expect(record.status, 'ok');
    expect(record.filePath, zip.path);
    expect(record.checksum, sha256.convert(zip.readAsBytesSync()).toString());

    final archive = decodeZip(zip);
    expect(archive, contains('fianarana.sqlite'));
    expect(archive, contains('media/logo.txt'));
    final manifest = jsonDecode(utf8.decode(archive['manifest.json']!)) as Map<String, dynamic>;
    expect(manifest['format'], 'fianarana-backup-v1');
    expect(manifest['database'], 'fianarana.sqlite');
    expect(manifest['type'], 'manuel');
    expect((manifest['includes'] as Map)['media'], isTrue);
  });

  test('restaure la base et les médias depuis une archive', () async {
    dbFile().writeAsStringSync('base-v1');
    final media = Directory(p.join(dataDir.path, 'media'))..createSync(recursive: true);
    File(p.join(media.path, 'photo.txt')).writeAsStringSync('photo-v1');

    final zip = await service.createBackup();

    // Dégradation simulée du dossier de données
    dbFile().writeAsStringSync('corrompu');
    dbFile('fianarana.sqlite-wal').writeAsStringSync('wal');
    media.deleteSync(recursive: true);

    await service.restoreFrom(zip.path);

    expect(dbFile().readAsStringSync(), 'base-v1');
    expect(dbFile('fianarana.sqlite-wal').existsSync(), isFalse);
    expect(File(p.join(dataDir.path, 'media', 'photo.txt')).readAsStringSync(), 'photo-v1');
  });

  test('cible la base bac à sable quand elle est active', () async {
    sandboxMarkerFile(dataDir).writeAsStringSync('1');
    dbFile('fianarana_sandbox.sqlite').writeAsStringSync('sandbox-v1');

    final zip = await service.createBackup(type: 'sandbox');
    final archive = decodeZip(zip);
    expect(archive, contains('fianarana_sandbox.sqlite'));
    expect(archive, isNot(contains('fianarana.sqlite')));
    final manifest = jsonDecode(utf8.decode(archive['manifest.json']!)) as Map<String, dynamic>;
    expect(manifest['database'], 'fianarana_sandbox.sqlite');
    expect(manifest['sandbox'], isTrue);

    dbFile('fianarana_sandbox.sqlite').writeAsStringSync('corrompu');
    await service.restoreFrom(zip.path);
    expect(dbFile('fianarana_sandbox.sqlite').readAsStringSync(), 'sandbox-v1');
  });

  test('refuse une archive inexistante', () async {
    expect(
      () => service.restoreFrom(p.join(dataDir.path, 'absent.zip')),
      throwsA(isA<StateError>()),
    );
  });
}

/// Décode une archive de sauvegarde en mémoire (nom -> contenu).
Map<String, List<int>> decodeZip(File zip) {
  final decoded = ZipDecoder().decodeBytes(zip.readAsBytesSync());
  final result = <String, List<int>>{};
  for (final file in decoded.files) {
    if (file.isFile) {
      final name = file.name.replaceAll('\\', '/');
      result[name] = file.content as List<int>;
    }
  }
  return result;
}
