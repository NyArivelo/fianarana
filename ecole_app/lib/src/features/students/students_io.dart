import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

class StudentsIO {
  static const headers = [
    'matricule', 'lastName', 'firstName', 'gender', 'birthDate', 'birthPlace', 'status', 'notes',
    'academicYear', 'className', 'enrollmentStatus',
    'guardianLastName', 'guardianFirstName', 'guardianPhone', 'guardianRelation', 'guardianEmail',
  ];

  static const baseHeaders = ['matricule', 'lastName', 'firstName', 'gender', 'birthDate', 'birthPlace', 'status', 'notes'];

  static String toCsvFromRows(List<Map<String, String>> rowsData) {
    final rows = <List<dynamic>>[headers];
    for (final r in rowsData) {
      rows.add([for (final h in headers) r[h] ?? '']);
    }
    return const ListToCsvConverter().convert(rows);
  }

  static List<int> toXlsxFromRows(List<Map<String, String>> rowsData) {
    final excel = Excel.createExcel();
    final sheet = excel['Eleves'];
    excel.setDefaultSheet('Eleves');
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
    for (final r in rowsData) {
      sheet.appendRow([for (final h in headers) TextCellValue(r[h] ?? '')]);
    }
    return excel.encode() ?? [];
  }

  static Future<List<Map<String, String>>> parseFile(String path) async {
    final lower = path.toLowerCase();
    if (lower.endsWith('.csv')) {
      final content = await File(path).readAsString(encoding: utf8);
      return parseCsv(content);
    } else if (lower.endsWith('.xlsx')) {
      final bytes = await File(path).readAsBytes();
      return parseXlsx(bytes);
    }
    throw Exception('Format non supporté. Utilisez .csv ou .xlsx');
  }

  static List<Map<String, String>> parseCsv(String content) {
    final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false).convert(content.replaceAll('\r\n', '\n'));
    if (rows.isEmpty) return [];
    final header = rows.first.map((e) => e.toString().trim()).toList();
    final out = <Map<String, String>>[];
    for (int i = 1; i < rows.length; i++) {
      final r = rows[i];
      if (r.every((c) => c.toString().trim().isEmpty)) continue;
      final map = <String, String>{};
      for (int j = 0; j < header.length && j < r.length; j++) {
        map[header[j]] = r[j].toString().trim();
      }
      out.add(map);
    }
    return out;
  }

  static List<Map<String, String>> parseXlsx(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return [];
    final sheet = excel.tables.values.first;
    if (sheet.rows.isEmpty) return [];
    final header = sheet.rows.first.map((c) => c?.value?.toString().trim() ?? '').toList();
    final out = <Map<String, String>>[];
    for (int i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.every((c) => (c?.value?.toString().trim() ?? '').isEmpty)) continue;
      final map = <String, String>{};
      for (int j = 0; j < header.length && j < row.length; j++) {
        map[header[j]] = row[j]?.value?.toString().trim() ?? '';
      }
      out.add(map);
    }
    return out;
  }
}

class ImportPreviewRow {
  final Map<String, String> data;
  final String status; // new, duplicate_db, duplicate_file, invalid
  final String message;
  ImportPreviewRow(this.data, this.status, this.message);
}
