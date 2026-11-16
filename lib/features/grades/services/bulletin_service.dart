import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class BulletinStudentData {
  final String fullName;
  final String matricule;
  final String? classLabel;
  final String? periodLabel;
  final List<BulletinSubjectLine> subjects;
  final double? average;
  final int? rank;
  final String? mention;
  final String? councilDecision;
  final String? appreciation;

  BulletinStudentData({
    required this.fullName,
    required this.matricule,
    this.classLabel,
    this.periodLabel,
    required this.subjects,
    this.average,
    this.rank,
    this.mention,
    this.councilDecision,
    this.appreciation,
  });
}

class BulletinSubjectLine {
  final String subject;
  final double? score;
  final double maxScore;
  final double coefficient;
  final bool isExempt;
  final String? observation;

  BulletinSubjectLine({
    required this.subject,
    this.score,
    required this.maxScore,
    required this.coefficient,
    this.isExempt = false,
    this.observation,
  });
}

/// Génération PDF native (Dart) des bulletins/relevés.
/// Donnée fonctionnelle: produit un document imprimable; la personnalisation Document Studio viendra ensuite.
class BulletinService {
  Future<Uint8List> generateStudentBulletin(BulletinStudentData data, {String? establishmentName}) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(establishmentName ?? 'Établissement scolaire', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Bulletin de notes ${data.periodLabel != null ? "- ${data.periodLabel}" : ""}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Élève: ${data.fullName}'),
              pw.Text('Matricule: ${data.matricule}'),
              if (data.classLabel != null) pw.Text('Classe: ${data.classLabel}'),
            ]),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['Matière', 'Note', 'Barème', 'Coef', 'Observation'],
            data: data.subjects.map((s) => [
              s.subject,
              s.isExempt ? 'Dispensé' : (s.score?.toStringAsFixed(2) ?? '-'),
              s.maxScore.toStringAsFixed(0),
              s.coefficient.toStringAsFixed(2),
              s.observation ?? '',
            ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Moyenne générale: ${data.average?.toStringAsFixed(2) ?? "-"} / 20'),
              if (data.rank != null) pw.Text('Rang: ${data.rank}'),
              if (data.mention != null) pw.Text('Mention: ${data.mention}'),
              if (data.councilDecision != null) pw.Text('Décision du conseil: ${data.councilDecision}'),
              if (data.appreciation != null) pw.Text('Appréciation: ${data.appreciation}'),
            ]),
          ),
          pw.SizedBox(height: 20),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Visa du responsable'),
            pw.Text('Visa de la direction'),
          ]),
          pw.SizedBox(height: 24),
          pw.Text('Document généré par Fianarana - image des données au moment de la génération.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    );
    return doc.save();
  }
}
