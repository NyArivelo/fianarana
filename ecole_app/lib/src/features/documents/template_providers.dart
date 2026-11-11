import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import 'template_repository.dart';

final templateRepositoryProvider = Provider<TemplateRepository>((ref) {
  return TemplateRepository(ref.watch(appDatabaseProvider));
});

final templateCategoryFilterProvider = StateProvider<String>((ref) => 'all');

final documentTemplatesProvider = StreamProvider<List<DocumentTemplate>>((ref) {
  return ref
      .watch(templateRepositoryProvider)
      .watchTemplates(category: ref.watch(templateCategoryFilterProvider));
});
