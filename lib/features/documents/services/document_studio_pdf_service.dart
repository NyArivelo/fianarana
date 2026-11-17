import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:fianarana/features/documents/services/document_template_engine.dart';

class DocumentStudioPdfService {
  final _engine = DocumentTemplateEngine();

  Future<Uint8List> renderTemplate({
    required Map<String, dynamic> templateContent,
    required Map<String, dynamic> context,
    String pageFormat = 'A4',
  }) async {
    final doc = pw.Document();
    final format = pageFormat.toUpperCase() == 'A5' ? PdfPageFormat.a5 : PdfPageFormat.a4;
    final title = _engine.render((templateContent['title'] ?? '').toString(), context);
    final header = _engine.render((templateContent['header'] ?? '').toString(), context);
    final intro = _engine.render((templateContent['intro'] ?? '').toString(), context);
    final body = _engine.render((templateContent['body'] ?? '').toString(), context);
    final footer = _engine.render((templateContent['footer'] ?? '').toString(), context);

    pw.Widget textBlock(String text, {double size = 11, bool bold = false, pw.TextAlign align = pw.TextAlign.left}) {
      if (text.trim().isEmpty) return pw.SizedBox.shrink();
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(text,
            textAlign: align,
            style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          if (header.isNotEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 8),
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400))),
              child: textBlock(header, size: 11),
            ),
          if (title.isNotEmpty) textBlock(title, size: 16, bold: true, align: pw.TextAlign.center),
          pw.SizedBox(height: 8),
          textBlock(intro),
          if (body.isNotEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
              child: textBlock(body),
            ),
          pw.Spacer(),
          if (footer.isNotEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.only(top: 8),
              decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300))),
              child: textBlock(footer, size: 9),
            ),
        ],
      ),
    );
    return doc.save();
  }

  /// Contexte de démonstration pour prévisualisation dans le studio.
  Map<String, dynamic> sampleContext({String docType = 'bulletin'}) {
    final base = <String, dynamic>{
      'etablissement': {'nom': 'Collège & Lycée Privé (Secondaire 2 & 3)', 'adresse': 'Antananarivo, Madagascar'},
      'eleve': {'nom': 'RASOAMANANA Sitraka Nomena', 'matricule': 'ELV-2026-0001', 'classe': '3ème 1'},
      'annee': {'libelle': '2026-2027'},
      'periode': {'libelle': 'Trimestre 1'},
      'date': {'jour': _today()},
      'resultats': {'moyenne': '13.75', 'rang': '5', 'mention': 'Assez bien', 'appreciation': 'Bon trimestre, efforts à poursuivre.'},
      'recu': {'numero': 'REC-2026-0001', 'date': _today(), 'libelle': 'Inscription + Écolage 2026-2027', 'du': '350000', 'paye': '350000', 'reste': '0', 'mode': 'Espèces'},
      'sortie': {'date': _today(), 'motif': 'Transfert vers un autre établissement', 'quitus_finance': 'Oui', 'quitus_bibliotheque': 'Oui'},
    };
    return base;
  }

  String _today() {
    final n = DateTime.now();
    return '${n.day.toString().padLeft(2, '0')}/${n.month.toString().padLeft(2, '0')}/${n.year}';
  }
}
