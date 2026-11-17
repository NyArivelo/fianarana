import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/documents/data/document_repository.dart';

final documentRepositoryProvider = Provider<DocumentRepository>((ref) => DocumentRepository(ref.watch(appDatabaseProvider)));

final documentTemplatesProvider = FutureProvider.autoDispose<List>((ref) async {
  final repo = ref.watch(documentRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  await repo.ensureDefaultTemplates();
  return repo.listTemplates(actorUserId: auth.userId);
});
