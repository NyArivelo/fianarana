import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/database/app_database.dart';

class DocumentService {
  final money = NumberFormat('#,##0.00', 'fr');
  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  Future<Uint8List> buildPaymentReceipt({
    required Payment payment,
    required Student student,
    FeeType? feeType,
    SchoolSetting? school,
  }) async {
    final doc = pw.Document();
    final schoolName = school?.name ?? 'Établissement scolaire';
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(schoolName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            if (school?.address != null) pw.Text(school!.address!),
            if (school?.phone != null) pw.Text('Tél: ${school!.phone}'),
            pw.SizedBox(height: 12),
            pw.Center(child: pw.Text('REÇU DE PAIEMENT', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 12),
            pw.Divider(),
            _row('N° Reçu', payment.receiptNumber),
            _row('Date', dateFmt.format(payment.paidAt)),
            _row('Élève', '${student.lastName} ${student.firstName}'),
            _row('Matricule', student.matricule),
            _row('Motif', feeType?.name ?? 'Frais scolaires'),
            _row('Mode', payment.method),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all()),
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Montant payé', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(money.format(payment.amount), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ]),
            ),
            if (payment.note != null && payment.note!.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text('Note: ${payment.note}'),
            ],
            pw.Spacer(),
            pw.Divider(),
            pw.Text('Document généré par l\'application de gestion scolaire.', style: const pw.TextStyle(fontSize: 9)),
            if (school?.legalMentions != null) pw.Text(school!.legalMentions!, style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ),
    );
    return doc.save();
  }

  Future<Uint8List> buildStudentCertificate({
    required Student student,
    required SchoolSetting? school,
    String title = 'CERTIFICAT DE SCOLARITÉ',
    String body = 'Certifie que l\'élève mentionné ci-dessus est régulièrement inscrit(e) dans notre établissement.',
  }) async {
    final doc = pw.Document();
    final schoolName = school?.name ?? 'Établissement scolaire';
    final now = DateFormat('dd/MM/yyyy').format(DateTime.now());
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(child: pw.Text(schoolName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
            if (school?.address != null) pw.Center(child: pw.Text(school!.address!)),
            pw.SizedBox(height: 24),
            pw.Center(child: pw.Text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 24),
            pw.Text('Nom et prénom : ${student.lastName} ${student.firstName}', style: const pw.TextStyle(fontSize: 12)),
            pw.Text('Matricule : ${student.matricule}', style: const pw.TextStyle(fontSize: 12)),
            if (student.birthDate != null)
              pw.Text('Date de naissance : ${DateFormat('dd/MM/yyyy').format(student.birthDate!)}', style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 16),
            pw.Text(body, style: const pw.TextStyle(fontSize: 12)),
            pw.Spacer(),
            pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Fait le $now')),
            pw.SizedBox(height: 40),
            pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Signature et cachet')),
          ],
        ),
      ),
    );
    return doc.save();
  }

  Future<Uint8List> buildBulletin({
    required Student student,
    required SchoolSetting? school,
    required List<Map<String, dynamic>> lines, // {subject, average, coef}
    String periodLabel = 'Période',
    String? appreciation,
    String? decision,
    int? rank,
    int? totalStudents,
  }) async {
    final doc = pw.Document();
    final schoolName = school?.name ?? 'Établissement scolaire';
    final dateStr = DateFormat('dd/MM/yyyy').format(DateTime.now());
    double total = 0;
    double coefSum = 0;
    for (final l in lines) {
      final avg = (l['average'] as num).toDouble();
      final coef = (l['coef'] as num?)?.toDouble() ?? 1.0;
      total += avg * coef;
      coefSum += coef;
    }
    final general = coefSum > 0 ? total / coefSum : null;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Text(schoolName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          if (school?.address != null) pw.Text(school!.address!),
          pw.SizedBox(height: 12),
          pw.Center(child: pw.Text('BULLETIN DE NOTES - $periodLabel', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 12),
          pw.Text('Élève: ${student.lastName} ${student.firstName}   Matricule: ${student.matricule}'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Matière', 'Moyenne /20', 'Coef'],
            data: [
              for (final l in lines)
                [l['subject'].toString(), ((l['average'] as num).toDouble()).toStringAsFixed(2), (l['coef'] ?? 1).toString()],
            ],
          ),
          pw.SizedBox(height: 12),
          if (general != null)
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all()),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('Moyenne générale: ${general.toStringAsFixed(2)} /20', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                if (rank != null && totalStudents != null) pw.Text('Rang: $rank / $totalStudents'),
              ]),
            ),
          if (appreciation != null && appreciation.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Appréciation du conseil de classe:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(appreciation),
          ],
          if (decision != null && decision.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Décision / orientation: $decision', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ],
          if (lines.isEmpty) pw.Text('Aucune note saisie pour la période sélectionnée.'),
          pw.SizedBox(height: 24),
          pw.Text('Édité le $dateStr', style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 120, child: pw.Text('$label :', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
          pw.Expanded(child: pw.Text(value)),
        ]),
      );
}
