import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';

class StudentsIO {
  static const headers = ['matricule', 'lastName', 'firstName', 'gender', 'birthDate', 'birthPlace', 'status', 'notes'];

  static String toCsv(List<Student> students) {
    final rows = <List<dynamic>>[headers];
    final fmt = DateFormat('yyyy-MM-dd');
    for (final s in students) {
      rows.add([
        s.matricule, s.lastName, s.firstName, s.gender ?? '', s.birthDate != null ? fmt.format(s.birthDate!) : '', s.birthPlace ?? '', s.status, s.notes ?? '',
      ]);
    }
    return const ListToCsvConverter().convert(rows);
  }

  static List<int> toXlsx(List<Student> students) {
    final excel = Excel.createExcel();
    final sheet = excel['Eleves'];
    excel.setDefaultSheet('Eleves');
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
    final fmt = DateFormat('yyyy-MM-dd');
    for (final s in students) {
      sheet.appendRow([
        TextCellValue(s.matricule),
        TextCellValue(s.lastName),
        TextCellValue(s.firstName),
        TextCellValue(s.gender ?? ''),
        TextCellValue(s.birthDate != null ? fmt.format(s.birthDate!) : ''),
        TextCellValue(s.birthPlace ?? ''),
        TextCellValue(s.status),
        TextCellValue(s.notes ?? ''),
      ]);
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
