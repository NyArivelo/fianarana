import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

class GradeImportRow {
  final String studentMatricule;
  final String? studentId;
  final String? studentName;
  final String subjectLabel;
  final String? subjectId;
  final String periodLabel;
  final String? periodId;
  final String evalLabel;
  final double? score;
  final double maxScore;
  final double coefficient;
  final bool isExempt;
  final String? masteryLevel;
  final String? observation;
  final bool duplicate;
  final String? error;

  GradeImportRow({
    required this.studentMatricule,
    required this.studentId,
    required this.studentName,
    required this.subjectLabel,
    required this.subjectId,
    required this.periodLabel,
    required this.periodId,
    required this.evalLabel,
    required this.score,
    required this.maxScore,
    required this.coefficient,
    required this.isExempt,
    required this.masteryLevel,
    required this.observation,
    required this.duplicate,
    required this.error,
  });
}

class GradesImportService {
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
      for (final e in m.entries) {
        final ek = e.key.toLowerCase().replaceAll(' ', '_');
        if (ek == k.toLowerCase().replaceAll(' ', '_') && e.value.trim().isNotEmpty) {
          return e.value.trim();
        }
      }
    }
    return null;
  }

  double? _parseDouble(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    return double.tryParse(s.replaceAll(',', '.'));
  }

  List<GradeImportRow> toRows(
    List<Map<String, String>> raw, {
    required Map<String, String> studentIdByMatricule,
    required Map<String, String> studentNameByMatricule,
    required Map<String, String> subjectIdByLabel,
    required Map<String, String> periodIdByLabel,
  }) {
    final seen = <String>{};
    return raw.map((m) {
      final mat = _pick(m, ['Matricule_Eleve', 'Matricule', 'matricule']) ?? '';
      final subj = _pick(m, ['Matiere', 'Matière', 'subject']) ?? '';
      final per = _pick(m, ['Periode', 'Période', 'period']) ?? '';
      final label = _pick(m, ['Libelle_Evaluation', 'Libelle', 'label']) ?? 'Évaluation';
      final studentId = studentIdByMatricule[mat];
      final subjectId = subjectIdByLabel[subj.toLowerCase()];
      final periodId = periodIdByLabel[per.toLowerCase()];
      final maxScore = _parseDouble(_pick(m, ['Bareme', 'Barème', 'maxScore'])) ?? 20;
      final coef = _parseDouble(_pick(m, ['Coefficient', 'coef'])) ?? 1;
      final exemptStr = (_pick(m, ['Dispense', 'Exempt']) ?? 'false').toLowerCase();
      final isExempt = exemptStr == 'true' || exemptStr == '1' || exemptStr == 'oui';
      final score = _parseDouble(_pick(m, ['Note', 'score']));
      final mastery = _pick(m, ['Niveau_Maitrise', 'Maitrise', 'masteryLevel']);
      final obs = _pick(m, ['Observation', 'observation']);

      String? err;
      if (mat.isEmpty) err = 'Matricule élève requis';
      if (studentId == null) err = (err == null) ? 'Élève introuvable ($mat)' : '$err; élève introuvable';
      if (subj.isEmpty) err = (err == null) ? 'Matière requise' : '$err; matière requise';
      if (subjectId == null && subj.isNotEmpty) err = (err == null) ? 'Matière introuvable ($subj)' : '$err; matière introuvable';
      if (per.isEmpty) err = (err == null) ? 'Période requise' : '$err; période requise';
      if (periodId == null && per.isNotEmpty) err = (err == null) ? 'Période introuvable ($per)' : '$err; période introuvable';
      if (!isExempt && score == null && (mastery == null || mastery.isEmpty)) {
        err = (err == null) ? 'Note ou niveau de maîtrise requis (ou dispense)' : '$err; note/maîtrise manquante';
      }

      final key = '$studentId|$subjectId|$periodId|$label';
      final dup = studentId != null && !seen.add(key);

      return GradeImportRow(
        studentMatricule: mat,
        studentId: studentId,
        studentName: studentNameByMatricule[mat],
        subjectLabel: subj,
        subjectId: subjectId,
        periodLabel: per,
        periodId: periodId,
        evalLabel: label,
        score: score,
        maxScore: maxScore,
        coefficient: coef,
        isExempt: isExempt,
        masteryLevel: mastery,
        observation: obs,
        duplicate: dup,
        error: err ?? (dup ? 'Doublon dans le fichier (élève/matière/période/libellé)' : null),
      );
    }).toList();
  }
}
