import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppPreferences extends ChangeNotifier {
  double uiScale = 1.0;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(dir.path, 'ecole_app'));
    if (!await dbDir.exists()) await dbDir.create(recursive: true);
    return File(p.join(dbDir.path, 'app_preferences.json'));
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      uiScale = ((data['uiScale'] as num?)?.toDouble() ?? 1.0).clamp(0.8, 1.6);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setUiScale(double value) async {
    uiScale = value.clamp(0.8, 1.6);
    notifyListeners();
    try {
      final f = await _file();
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert({'uiScale': uiScale}));
    } catch (_) {}
  }
}

final appPreferencesProvider = ChangeNotifierProvider<AppPreferences>((ref) => AppPreferences());
