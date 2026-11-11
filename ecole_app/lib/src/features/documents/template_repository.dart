import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class TemplateRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  TemplateRepository(this.db);

  Stream<List<DocumentTemplate>> watchTemplates({String? category}) {
    final q = db.select(db.documentTemplates)..where((t) => t.isDeleted.equals(false));
    if (category != null && category.isNotEmpty && category != 'all') {
      q.where((t) => t.category.equals(category));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch();
  }

  Future<void> upsertTemplate({
    String? id,
    required String name,
    String category = 'general',
    String? title,
    required String body,
    bool isActive = true,
  }) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.documentTemplates).insert(DocumentTemplatesCompanion.insert(
            id: _uuid.v4(),
            name: name,
            category: Value(category),
            title: Value(title),
            body: body,
            isActive: Value(isActive),
          ));
    } else {
      await (db.update(db.documentTemplates)..where((t) => t.id.equals(id))).write(
        DocumentTemplatesCompanion(
          name: Value(name),
          category: Value(category),
          title: Value(title),
          body: Value(body),
          isActive: Value(isActive),
          updatedAt: Value(now),
        ),
      );
    }
  }

  Future<void> deleteTemplate(String id) async {
    await (db.update(db.documentTemplates)..where((t) => t.id.equals(id))).write(
      DocumentTemplatesCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())),
    );
  }
}
