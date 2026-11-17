import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';

const kUiScaleKey = 'ui_scale';
const kDefaultUiScale = 1.0;

final uiScaleProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final row = await (db.select(db.appSettings)..where((t) => t.key.equals(kUiScaleKey))).getSingleOrNull();
  final v = double.tryParse(row?.value ?? '');
  if (v == null) return kDefaultUiScale;
  return v.clamp(0.85, 1.25);
});

Future<void> saveUiScale(WidgetRef ref, double scale) async {
  final db = ref.read(appDatabaseProvider);
  final s = scale.clamp(0.85, 1.25).toStringAsFixed(2);
  await db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: kUiScaleKey, value: Value(s)));
  ref.invalidate(uiScaleProvider);
}
