import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CsvExport {
  static String _escape(String? v) {
    final s = (v ?? '').replaceAll('"', '""');
    return '"$s"';
  }

  static Future<File> export({required String filename, required List<String> headers, required List<List<String?>> rows}) async {
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(dir.path, 'fianarana_exports'));
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final file = File(p.join(outDir.path, filename));
    final sb = StringBuffer();
    sb.writeln(headers.map(_escape).join(','));
    for (final r in rows) {
      sb.writeln(r.map(_escape).join(','));
    }
    await file.writeAsString(sb.toString());
    return file;
  }
}
