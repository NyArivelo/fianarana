import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'backup_service.dart';

class AutoBackupService {
  final BackupService backupService;
  AutoBackupService(this.backupService);

  Future<File> _configFile() async {
    final dir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(dir.path, 'ecole_app'));
    if (!await dbDir.exists()) await dbDir.create(recursive: true);
    return File(p.join(dbDir.path, 'backup_config.json'));
  }

  Future<Map<String, dynamic>> loadConfig() async {
    final f = await _configFile();
    if (!await f.exists()) {
      return {'enabled': false, 'intervalHours': 24, 'directory': null, 'lastBackupAt': null};
    }
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {'enabled': false, 'intervalHours': 24, 'directory': null, 'lastBackupAt': null};
    }
  }

  Future<void> saveConfig(Map<String, dynamic> config) async {
    final f = await _configFile();
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(config));
  }

  Future<String?> maybeRunAutoBackup() async {
    final config = await loadConfig();
    if (config['enabled'] != true) return null;
    final intervalHours = (config['intervalHours'] as num?)?.toInt() ?? 24;
    final lastStr = config['lastBackupAt'] as String?;
    if (lastStr != null) {
      final last = DateTime.tryParse(lastStr);
      if (last != null && DateTime.now().difference(last).inHours < intervalHours) return null;
    }
    final dirPath = config['directory'] as String?;
    final backupDir = dirPath != null && dirPath.isNotEmpty ? Directory(dirPath) : Directory(p.join((await getApplicationSupportDirectory()).path, 'ecole_app', 'backups'));
    if (!await backupDir.exists()) await backupDir.create(recursive: true);
    final name = 'auto_backup_${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}.zip';
    final target = p.join(backupDir.path, name);
    await backupService.createBackup(target);
    config['lastBackupAt'] = DateTime.now().toIso8601String();
    await saveConfig(config);
    return target;
  }
}
