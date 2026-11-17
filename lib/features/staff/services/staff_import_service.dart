import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

class StaffImportRow {
  final String staffNumber;
  final String lastName;
  final String firstName;
  final String? sex;
  final String? functionTitle;
  final String? departmentOrSubject;
  final String? phone;
  final String? status;
  final bool duplicate;
  final String? error;

  StaffImportRow({
    required this.staffNumber,
    required this.lastName,
    required this.firstName,
    this.sex,
    this.functionTitle,
    this.departmentOrSubject,
    this.phone,
    this.status,
    this.duplicate = false,
    this.error,
  });
}

class StaffImportService {
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

  List<StaffImportRow> toRows(List<Map<String, String>> raw, Set<String> existingNumbers) {
    final seen = <String>{};
    return raw.map((m) {
      final num = _pick(m, ['Matricule_Personnel', 'Matricule', 'staffNumber', 'matricule']) ?? '';
      final last = _pick(m, ['Nom', 'lastName']) ?? '';
      final first = _pick(m, ['Prenom', 'Prénom', 'firstName']) ?? '';
      String? err;
      if (num.isEmpty) err = 'Matricule requis';
      if (last.isEmpty || first.isEmpty) err = (err == null) ? 'Nom et prénom requis' : '$err; nom/prénom requis';
      final dup = num.isNotEmpty && (existingNumbers.contains(num) || !seen.add(num));
      return StaffImportRow(
        staffNumber: num,
        lastName: last,
        firstName: first,
        sex: _pick(m, ['Sexe', 'sex']),
        functionTitle: _pick(m, ['Fonction', 'functionTitle']),
        departmentOrSubject: _pick(m, ['Departement_Matiere', 'Matiere', 'Service', 'departmentOrSubject']),
        phone: _pick(m, ['Telephone', 'phone']),
        status: _pick(m, ['Statut', 'status']),
        duplicate: dup,
        error: err ?? (dup ? 'Doublon matricule (existant ou fichier)' : null),
      );
    }).toList();
  }
}
