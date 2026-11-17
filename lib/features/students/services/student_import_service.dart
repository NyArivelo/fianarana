import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

class StudentImportRow {
  final String matricule;
  final String lastName;
  final String firstName;
  final String? sex;
  final String? birthDate; // YYYY-MM-DD
  final String? birthPlace;
  final String? classLabel;
  final String? status;
  final String? birthCertificateNumber;
  final String? nationalIdNumber;
  final bool duplicateMatricule;
  final String? error;
  StudentImportRow({
    required this.matricule,
    required this.lastName,
    required this.firstName,
    this.sex,
    this.birthDate,
    this.birthPlace,
    this.classLabel,
    this.status,
    this.birthCertificateNumber,
    this.nationalIdNumber,
    this.duplicateMatricule = false,
    this.error,
  });
  StudentImportRow copyWith({bool? duplicateMatricule, String? error}) => StudentImportRow(
        matricule: matricule,
        lastName: lastName,
        firstName: firstName,
        sex: sex,
        birthDate: birthDate,
        birthPlace: birthPlace,
        classLabel: classLabel,
        status: status,
        birthCertificateNumber: birthCertificateNumber,
        nationalIdNumber: nationalIdNumber,
        duplicateMatricule: duplicateMatricule ?? this.duplicateMatricule,
        error: error ?? this.error,
      );
}

class StudentImportService {
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
      final rows = const CsvToListConverter(shouldParseNumbers: false, eol: '\n').convert(content.replaceAll('\r\n', '\n'));
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
      final v = m[k] ?? m[k.toLowerCase()] ?? m[k.toUpperCase()];
      if (v != null && v.trim().isNotEmpty) return v.trim();
      // case-insensitive scan
      for (final e in m.entries) {
        if (e.key.toLowerCase().replaceAll(' ', '_') == k.toLowerCase().replaceAll(' ', '_') && e.value.trim().isNotEmpty) {
          return e.value.trim();
        }
      }
    }
    return null;
  }

  List<StudentImportRow> toRows(List<Map<String, String>> raw, Set<String> existingMatricules) {
    final seen = <String>{};
    return raw.map((m) {
      final matricule = _pick(m, ['Matricule', 'matricule', 'MATRICULE']) ?? '';
      final last = _pick(m, ['Nom', 'lastName', 'nom']) ?? '';
      final first = _pick(m, ['Prenom', 'Prénom', 'firstName', 'prenom']) ?? '';
      String? err;
      if (matricule.isEmpty) err = 'Matricule requis';
      if (last.isEmpty || first.isEmpty) err = (err == null) ? 'Nom et prénom requis' : '$err; nom/prénom requis';
      final dup = matricule.isNotEmpty && (existingMatricules.contains(matricule) || !seen.add(matricule));
      return StudentImportRow(
        matricule: matricule,
        lastName: last,
        firstName: first,
        sex: _pick(m, ['Sexe', 'sex']),
        birthDate: _pick(m, ['Date_Naissance', 'DateNaissance', 'birthDate']),
        birthPlace: _pick(m, ['Lieu_Naissance', 'LieuNaissance', 'birthPlace']),
        classLabel: _pick(m, ['Classe', 'class']),
        status: _pick(m, ['Statut', 'status']),
        birthCertificateNumber: _pick(m, ['Numero_Acte_Naissance', 'Acte_Naissance']),
        nationalIdNumber: _pick(m, ['Numero_ID_National', 'ID_National', 'CIN']),
        duplicateMatricule: dup,
        error: err ?? (dup ? 'Doublon matricule (existant ou fichier)' : null),
      );
    }).toList();
  }
}
