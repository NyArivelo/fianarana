import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class DisciplineRepository {
  final AppDatabase db;
  final _uuid = const Uuid();
  DisciplineRepository(this.db);

  Stream<List<DisciplinaryIncident>> watchIncidents({String? studentId, String? status, String query = ''}) {
    final q = db.select(db.disciplinaryIncidents)..where((t) => t.isDeleted.equals(false));
    if (studentId != null && studentId.isNotEmpty) q.where((t) => t.studentId.equals(studentId));
    if (status != null && status.isNotEmpty) q.where((t) => t.status.equals(status));
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim()}%';
      q.where((t) => t.incidentType.like(like) | t.description.like(like) | t.location.like(like));
    }
    q.orderBy([(t) => OrderingTerm.desc(t.incidentDate), (t) => OrderingTerm.desc(t.createdAt)]);
    return q.watch();
  }

  Future<String> upsertIncident({String? id, required String studentId, required DateTime incidentDate, required String incidentType, required String description, String? location, String? reportedBy, String status = 'open', bool isConfidential = true}) async {
    final now = DateTime.now();
    if (id == null) {
      final nid = _uuid.v4();
      await db.into(db.disciplinaryIncidents).insert(DisciplinaryIncidentsCompanion.insert(id: nid, studentId: studentId, incidentDate: incidentDate, incidentType: incidentType, description: description, location: Value(location), reportedBy: Value(reportedBy), status: Value(status), isConfidential: Value(isConfidential)));
      return nid;
    }
    await (db.update(db.disciplinaryIncidents)..where((t)=>t.id.equals(id))).write(DisciplinaryIncidentsCompanion(studentId: Value(studentId), incidentDate: Value(incidentDate), incidentType: Value(incidentType), description: Value(description), location: Value(location), reportedBy: Value(reportedBy), status: Value(status), isConfidential: Value(isConfidential), updatedAt: Value(now)));
    return id;
  }

  Future<void> deleteIncident(String id) async {
    await (db.update(db.disciplinaryIncidents)..where((t)=>t.id.equals(id))).write(DisciplinaryIncidentsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())));
  }

  Stream<List<DisciplinaryAction>> watchActions(String incidentId) {
    return (db.select(db.disciplinaryActions)..where((t)=>t.incidentId.equals(incidentId) & t.isDeleted.equals(false))..orderBy([(t)=>OrderingTerm.desc(t.decisionDate),(t)=>OrderingTerm.desc(t.createdAt)])).watch();
  }

  Future<void> upsertAction({String? id, required String incidentId, required String actionType, DateTime? decisionDate, DateTime? startDate, DateTime? endDate, String? notes, String executionStatus = 'planned', String? followUpNotes}) async {
    final now = DateTime.now();
    if (id == null) {
      await db.into(db.disciplinaryActions).insert(DisciplinaryActionsCompanion.insert(id: _uuid.v4(), incidentId: incidentId, actionType: actionType, decisionDate: Value(decisionDate), startDate: Value(startDate), endDate: Value(endDate), notes: Value(notes), executionStatus: Value(executionStatus), followUpNotes: Value(followUpNotes)));
    } else {
      await (db.update(db.disciplinaryActions)..where((t)=>t.id.equals(id))).write(DisciplinaryActionsCompanion(actionType: Value(actionType), decisionDate: Value(decisionDate), startDate: Value(startDate), endDate: Value(endDate), notes: Value(notes), executionStatus: Value(executionStatus), followUpNotes: Value(followUpNotes), updatedAt: Value(now)));
    }
  }

  Future<void> deleteAction(String id) async {
    await (db.update(db.disciplinaryActions)..where((t)=>t.id.equals(id))).write(DisciplinaryActionsCompanion(isDeleted: const Value(true), deletedAt: Value(DateTime.now())));
  }
}
