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
  final int discount;
  final int scholarship;
  final int creditNote;
  final int netDue;
  final String? establishmentAddress;
  final String? establishmentPhone;

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
    this.discount = 0,
    this.scholarship = 0,
    this.creditNote = 0,
    this.netDue = 0,
    this.establishmentAddress,
    this.establishmentPhone,
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
          if (data.establishmentAddress != null && data.establishmentAddress!.isNotEmpty)
            pw.Text(data.establishmentAddress!, style: const pw.TextStyle(fontSize: 9)),
          if (data.establishmentPhone != null && data.establishmentPhone!.isNotEmpty)
            pw.Text('Tél. ${data.establishmentPhone}', style: const pw.TextStyle(fontSize: 9)),
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
          if (data.discount > 0) pw.Text('Remise: -${data.discount} MGA'),
          if (data.scholarship > 0) pw.Text('Bourse: -${data.scholarship} MGA'),
          if (data.creditNote > 0) pw.Text('Avoir utilisé: -${data.creditNote} MGA'),
          if (data.discount + data.scholarship + data.creditNote > 0)
            pw.Text('Net à payer: ${data.netDue > 0 ? data.netDue : data.amountDue} MGA',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
