import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ReceiptData {
  final String receiptNumber;
  final DateTime? date;
  final String studentName;
  final String matricule;
  final String? classLabel;
  final String feeLabel;
  final int amountDue;
  final int amountPaid;
  final int balance;
  final String? paymentMethod;
  final String? cashier;

  ReceiptData({
    required this.receiptNumber,
    required this.date,
    required this.studentName,
    required this.matricule,
    this.classLabel,
    required this.feeLabel,
    required this.amountDue,
    required this.amountPaid,
    required this.balance,
    this.paymentMethod,
    this.cashier,
  });
}

class ReceiptService {
  Future<Uint8List> generateReceipt(ReceiptData data, {String? establishmentName}) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(establishmentName ?? 'Établissement scolaire', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('REÇU DE PAIEMENT', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          pw.Text('N° Reçu: ${data.receiptNumber}'),
          pw.Text('Date: ${data.date != null ? "${data.date!.year}-${data.date!.month.toString().padLeft(2,'0')}-${data.date!.day.toString().padLeft(2,'0')}" : "-"}'),
          pw.SizedBox(height: 8),
          pw.Text('Élève: ${data.studentName} (${data.matricule})'),
          if (data.classLabel != null) pw.Text('Classe: ${data.classLabel}'),
          pw.SizedBox(height: 8),
          pw.Text('Libellé: ${data.feeLabel}'),
          pw.Text('Montant dû: ${data.amountDue} MGA'),
          pw.Text('Montant payé: ${data.amountPaid} MGA', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text('Reste à payer: ${data.balance} MGA'),
          if (data.paymentMethod != null) pw.Text('Mode: ${data.paymentMethod}'),
          if (data.cashier != null) pw.Text('Caissier: ${data.cashier}'),
          pw.Spacer(),
          pw.Divider(),
          pw.Text('Merci pour votre paiement.', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Document généré par Fianarana.', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ]),
      ),
    );
    return doc.save();
  }
}
