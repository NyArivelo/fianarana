import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ExitCertificateData {
  final String studentName;
  final String matricule;
  final String? classLabel;
  final DateTime? birthDate;
  final String? birthPlace;
  final DateTime exitDate;
  final String reason;
  final String schoolYearLabel;
  final bool financeClearance;
  final bool libraryClearance;

  const ExitCertificateData({
    required this.studentName,
    required this.matricule,
    required this.classLabel,
    required this.birthDate,
    required this.birthPlace,
    required this.exitDate,
    required this.reason,
    required this.schoolYearLabel,
    required this.financeClearance,
    required this.libraryClearance,
  });
}

class CertificateService {
  Future<Uint8List> generateExitCertificate(
    ExitCertificateData data, {
    String? establishmentName,
    String? establishmentAddress,
  }) async {
    final doc = pw.Document();
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Column(children: [
                pw.Text(establishmentName ?? 'Établissement scolaire',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                if (establishmentAddress != null)
                  pw.Text(establishmentAddress, style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 8),
                pw.Text('CERTIFICAT DE RADIATION / CERTIFICAT DE SORTIE',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                pw.Text('Année scolaire ${data.schoolYearLabel}',
                    style: const pw.TextStyle(fontSize: 11)),
              ]),
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'Le chef d\'établissement certifie que l\'élève ci-après désigné(e) a été régulièrement inscrit(e) '
              'et quitte l\'établissement à la date indiquée, après accomplissement des formalités de sortie.',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey700)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                _row('Nom et prénom', data.studentName),
                _row('Matricule', data.matricule),
                _row('Classe', data.classLabel ?? '-'),
                _row('Date et lieu de naissance',
                    '${data.birthDate != null ? fmt(data.birthDate!) : '-'}${data.birthPlace != null && data.birthPlace!.isNotEmpty ? ' à ${data.birthPlace}' : ''}'),
                _row('Date de sortie / radiation', fmt(data.exitDate)),
                _row('Motif', data.reason),
              ]),
            ),
            pw.SizedBox(height: 14),
            pw.Text('Quitus et régularisation :',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            _check('Quitus financier (scolarité/frais régularisés)', data.financeClearance),
            _check('Quitus bibliothèque (aucun ouvrage en cours)', data.libraryClearance),
            pw.SizedBox(height: 18),
            pw.Text(
              'Le présent certificat est délivré pour servir et valoir ce que de droit. '
              'L\'historique scolaire et administratif de l\'élève est conservé intégralement dans les archives de l\'établissement.',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Spacer(),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Column(children: [
                pw.Text('Cachet et signature de l\'établissement', style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 40),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('Fait le ${fmt(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 40),
              ]),
            ]),
            pw.Divider(),
            pw.Text('Document généré par Fianarana — Certificat de sortie/radiation.',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ],
        ),
      ),
    );
    return doc.save();
  }

  pw.Widget _row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 170, child: pw.Text('$label :', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
          pw.Expanded(child: pw.Text(value, style: const pw.TextStyle(fontSize: 10))),
        ]),
      );

  pw.Widget _check(String label, bool ok) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(children: [
          pw.Container(
            width: 10,
            height: 10,
            decoration: pw.BoxDecoration(border: pw.Border.all()),
            child: ok ? pw.Center(child: pw.Text('X', style: const pw.TextStyle(fontSize: 8))) : null,
          ),
          pw.SizedBox(width: 6),
          pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
        ]),
      );
}
