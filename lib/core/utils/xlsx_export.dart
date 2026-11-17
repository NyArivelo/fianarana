import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class XlsxExport {
  static Future<File> export({
    required String filename,
    required String sheetName,
    required List<String> headers,
    required List<List<String?>> rows,
  }) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheetName) {
      excel.rename(defaultSheet, sheetName);
    }
    final sheet = excel[sheetName];
    for (var c = 0; c < headers.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .value = TextCellValue(headers[c]);
    }
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      for (var c = 0; c < headers.length && c < row.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
            .value = TextCellValue(row[c] ?? '');
      }
    }
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(dir.path, 'fianarana_exports'));
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final file = File(p.join(outDir.path, filename));
    final bytes = excel.encode();
    if (bytes != null) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file;
  }
}
