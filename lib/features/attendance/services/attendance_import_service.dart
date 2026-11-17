import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

class AttendanceImportRow {
  final String matricule;
  final String dateStr;
  final DateTime? date;
  final String status;
  final String category;
  final String? classLabel;
  final String? slotOrFacts;
  final String? justification;
  final String? studentId;
  final String? studentName;
  final String? classId;
  final String? error;
  final bool duplicateKey;

  AttendanceImportRow({
    required this.matricule,
    required this.dateStr,
    required this.date,
    required this.status,
    required this.category,
    this.classLabel,
    this.slotOrFacts,
    this.justification,
    this.studentId,
    this.studentName,
    this.classId,
    this.error,
    this.duplicateKey = false,
  });

  AttendanceImportRow copyWith({String? studentId, String? studentName, String? classId, String? error, bool? duplicateKey}) => AttendanceImportRow(
        matricule: matricule,
        dateStr: dateStr,
        date: date,
        status: status,
        category: category,
        classLabel: classLabel,
        slotOrFacts: slotOrFacts,
        justification: justification,
        studentId: studentId ?? this.studentId,
        studentName: studentName ?? this.studentName,
        classId: classId ?? this.classId,
        error: error ?? this.error,
        duplicateKey: duplicateKey ?? this.duplicateKey,
      );
}

class AttendanceImportService {
  static const templateHeaders = <String>[
    'Matricule_Eleve',
    'Date', // YYYY-MM-DD
    'Classe',
    'Statut', // Présent, Absent, Retard, Incident...
    'Categorie', // Appel / Présence, Discipline, Santé, Autorisation
    'Creneau_Faits',
    'Justification',
  ];

  static const templateSample = <List<String>>[
    ['ELEVE-001', '2026-11-17', '6ème A', 'Présent', 'Appel / Présence', 'Matin', ''],
    ['ELEVE-002', '2026-11-17', '6ème A', 'Absent', 'Appel / Présence', 'Matin', 'Justificatif médical'],
  ];

  Future<List<Map<String, String>>> parseFile(File file) async {
    final path = file.path.toLowerCase();
    if (path.endsWith('.xlsx') || path.endsWith('.xls')) {
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) return [];
      final sheet = excel.tables.values.first;
      if (sheet == null || sheet.rows.isEmpty) return [];
      final headers = sheet.rows.first.map((c) => (c?.value?.toString() ?? '').trim()).toList();
      final out = <Map<String, String>>[];
      for (var i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        final map = <String, String>{};
        for (var j = 0; j < headers.length && j < row.length; j++) {
          final h = headers[j];
          if (h.isEmpty) continue;
          map[h] = row[j]?.value?.toString().trim() ?? '';
        }
        if (map.values.any((v) => v.isNotEmpty)) out.add(map);
      }
      return out;
    } else {
      final content = await file.readAsString(encoding: utf8);
      final rows = const CsvToListConverter(shouldParseNumbers: false, eol: '\n')
          .convert(content.replaceAll('\r\n', '\n'));
      if (rows.isEmpty) return [];
      final headers = rows.first.map((e) => e.toString().trim()).toList();
      final out = <Map<String, String>>[];
      for (var i = 1; i < rows.length; i++) {
        final r = rows[i];
        final map = <String, String>{};
        for (var j = 0; j < headers.length && j < r.length; j++) {
          final h = headers[j];
          if (h.isEmpty) continue;
          map[h] = r[j].toString().trim();
        }
        if (map.values.any((v) => v.isNotEmpty)) out.add(map);
      }
      return out;
    }
  }

  String? _pick(Map<String, String> m, List<String> keys) {
    for (final k in keys) {
      final want = k.toLowerCase().replaceAll(' ', '_');
      for (final e in m.entries) {
        final ek = e.key.toLowerCase().replaceAll(' ', '_');
        if (ek == want && e.value.trim().isNotEmpty) return e.value.trim();
      }
    }
    return null;
  }

  DateTime? _parseDate(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final s = v.trim();
    final d = DateTime.tryParse(s);
    if (d != null) return DateTime(d.year, d.month, d.day);
    // try DD/MM/YYYY
    final m = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$').firstMatch(s);
    if (m != null) {
      final dd = int.tryParse(m.group(1)!);
      final mm = int.tryParse(m.group(2)!);
      final yy = int.tryParse(m.group(3)!);
      if (dd != null && mm != null && yy != null) {
        return DateTime(yy, mm, dd);
      }
    }
    return null;
  }

  String _normStatus(String v) {
    final s = v.trim();
    if (s.isEmpty) return 'Présent';
    final l = s.toLowerCase();
    if (l.startsWith('pres') || l == 'present') return 'Présent';
    if (l.startsWith('abs')) return 'Absent';
    if (l.startsWith('ret')) return 'Retard';
    if (l.startsWith('inc')) return 'Incident';
    if (l.startsWith('just')) return 'Justifié';
    if (l.startsWith('excl')) return 'Exclusion';
    if (l.startsWith('res')) return 'Résolu';
    if (l.startsWith('clo')) return 'Clôturé';
    if (l.startsWith('enc')) return 'En cours';
    if (l.startsWith('aver')) return 'Avertissement';
    return s;
  }

  String _normCategory(String v) {
    final l = v.trim().toLowerCase();
    if (l.isEmpty) return 'Appel / Présence';
    if (l.contains('appel') || l.contains('presence') || l.contains('présence')) return 'Appel / Présence';
    if (l.contains('discip')) return 'Discipline';
    if (l.contains('sant')) return 'Santé';
    if (l.contains('autor')) return 'Autorisation';
    return v.trim();
  }

  List<AttendanceImportRow> toRows(
    List<Map<String, String>> raw, {
    required Map<String, String> studentIdByMatricule,
    required Map<String, String> studentNameByMatricule,
    Map<String, String>? classIdByLabel,
  }) {
    final seen = <String>{};
    final out = <AttendanceImportRow>[];
    for (final m in raw) {
      final matricule = _pick(m, ['Matricule_Eleve', 'Matricule', 'matricule_eleve']) ?? '';
      final dateStr = _pick(m, ['Date', 'date']) ?? '';
      final statusRaw = _pick(m, ['Statut', 'status']) ?? 'Présent';
      final catRaw = _pick(m, ['Categorie', 'Catégorie', 'category']) ?? 'Appel / Présence';
      final classLabel = _pick(m, ['Classe', 'class', 'classe']);
      final slot = _pick(m, ['Creneau_Faits', 'Créneau_Faits', 'Creneau', 'Créneau', 'slot']);
      final justif = _pick(m, ['Justification', 'justification', 'Sanction']);

      final date = _parseDate(dateStr);
      final status = _normStatus(statusRaw);
      final category = _normCategory(catRaw);
      String? error;
      if (matricule.isEmpty) error = 'Matricule élève manquant';
      if (date == null) error = (error == null) ? 'Date invalide (attendu YYYY-MM-DD)' : '$error; date invalide';
      final sid = studentIdByMatricule[matricule];
      final sname = studentNameByMatricule[matricule];
      if (error == null && sid == null) error = 'Élève introuvable (matricule)';
      String? classId;
      if (classLabel != null && classLabel.isNotEmpty && classIdByLabel != null) {
        classId = classIdByLabel[classLabel.toLowerCase()];
      }
      final key = '${matricule.toLowerCase()}|${date?.toIso8601String() ?? dateStr}|${category.toLowerCase()}';
      final dup = seen.contains(key);
      if (dup && error == null) error = 'Doublon dans le fichier (même élève/date/catégorie)';
      if (!dup) seen.add(key);
      out.add(AttendanceImportRow(
        matricule: matricule,
        dateStr: dateStr,
        date: date,
        status: status,
        category: category,
        classLabel: classLabel,
        slotOrFacts: slot,
        justification: justif,
        studentId: sid,
        studentName: sname,
        classId: classId,
        error: error,
        duplicateKey: dup,
      ));
    }
    return out;
  }
}
