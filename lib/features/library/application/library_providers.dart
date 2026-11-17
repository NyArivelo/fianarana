import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/library/data/library_repository.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(ref.watch(appDatabaseProvider));
});

final libraryCatalogueProvider = FutureProvider<List<LibraryCatalogueRow>>((ref) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(libraryRepositoryProvider).listCatalogue(actorUserId: userId);
});

final libraryLoansProvider = FutureProvider<List<LibraryLoanRow>>((ref) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(libraryRepositoryProvider).listLoans(actorUserId: userId);
});

final libraryStatsProvider = FutureProvider<LibraryStats>((ref) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref.watch(libraryRepositoryProvider).stats(actorUserId: userId);
});

final libraryQuitusProvider =
    FutureProvider.family<List<LibraryQuitusRow>, bool>((ref, includeAll) {
  final userId = ref.watch(authControllerProvider).userId;
  return ref
      .watch(libraryRepositoryProvider)
      .quitusRows(actorUserId: userId, includeAll: includeAll);
});
