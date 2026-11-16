import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/grades/application/grades_providers.dart';

final periodsProvider = FutureProvider((ref) => ref.watch(gradesRepositoryProvider).listPeriods());

final councilsProvider = FutureProvider.family((ref, ({String? classId, String? periodId}) args) {
  return ref.watch(gradesRepositoryProvider).listCouncils(classId: args.classId, periodId: args.periodId);
});
