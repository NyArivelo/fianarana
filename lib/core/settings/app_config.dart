import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';

const kInactivityMinutesKey = 'inactivity_minutes';
const kRecycleRetentionDaysKey = 'recycle_retention_days';
const kSandboxModeKey = 'sandbox_mode';
const kCivilStatusConfigKey = 'civil_status_config';

class AppConfig {
  final int inactivityMinutes;
  final int recycleRetentionDays;
  final bool sandboxMode;
  final Map<String, dynamic> civilStatusConfig;
  const AppConfig({required this.inactivityMinutes, required this.recycleRetentionDays, required this.sandboxMode, required this.civilStatusConfig});
  static const defaults = AppConfig(
    inactivityMinutes: 5,
    recycleRetentionDays: 30,
    sandboxMode: false,
    civilStatusConfig: {
      'fields': {
        'birthCertificateNumber': {'label': 'N° acte de naissance', 'required': false, 'enabled': true},
        'nationalIdNumber': {'label': 'N° identification nationale / CIN', 'required': false, 'enabled': true},
      }
    },
  );
}

final appConfigProvider = FutureProvider<AppConfig>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  Future<String?> get(String k) async => (await (db.select(db.appSettings)..where((t)=>t.key.equals(k))).getSingleOrNull())?.value;
  int parseInt(String? v, int def) => int.tryParse(v ?? '') ?? def;
  bool parseBool(String? v, bool def) => v == null ? def : (v == '1' || v.toLowerCase() == 'true');
  Map<String, dynamic> parseJson(String? v, Map<String, dynamic> def) {
    try { if (v==null||v.isEmpty) return def; final d=jsonDecode(v); return d is Map<String,dynamic>?d:def; } catch(_){ return def; }
  }
  return AppConfig(
    inactivityMinutes: parseInt(await get(kInactivityMinutesKey), 5).clamp(1, 120),
    recycleRetentionDays: parseInt(await get(kRecycleRetentionDaysKey), 30).clamp(1, 3650),
    sandboxMode: parseBool(await get(kSandboxModeKey), false),
    civilStatusConfig: parseJson(await get(kCivilStatusConfigKey), AppConfig.defaults.civilStatusConfig),
  );
});

Future<void> saveAppSetting(WidgetRef ref, String key, String value) async {
  final db = ref.read(appDatabaseProvider);
  await db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: Value(value)));
  ref.invalidate(appConfigProvider);
}
