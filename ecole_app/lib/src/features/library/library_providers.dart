import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import 'library_repository.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) => LibraryRepository(ref.watch(appDatabaseProvider)));

final librarySearchProvider = StateProvider<String>((ref) => '');

final libraryItemsProvider = StreamProvider<List<LibraryItem>>((ref) {
  return ref.watch(libraryRepositoryProvider).watchItems(query: ref.watch(librarySearchProvider));
});

final copiesForItemProvider = StreamProvider.family<List<LibraryCopy>, String>((ref, itemId) {
  return ref.watch(libraryRepositoryProvider).watchCopies(itemId);
});

final loansProvider = StreamProvider<List<LibraryLoan>>((ref) {
  ref.watch(libraryRepositoryProvider).refreshOverdue();
  return ref.watch(libraryRepositoryProvider).watchLoans();
});

final activeLoansForStudentProvider = StreamProvider.family<List<LibraryLoan>, String>((ref, studentId) {
  return ref.watch(libraryRepositoryProvider).watchActiveLoansForStudent(studentId);
});
