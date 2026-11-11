import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/database/app_database.dart';
import '../../core/security/current_user_scope.dart';
import '../finance/finance_providers.dart';
import '../settings/settings_providers.dart';
import '../students/students_providers.dart';
import 'document_service.dart';

final documentServiceProvider = Provider<DocumentService>((ref) => DocumentService());

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  String? _selectedPaymentId;
  String? _selectedStudentId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(tabs: [Tab(text: 'Reçu de paiement'), Tab(text: 'Certificat de scolarité')]),
          Expanded(child: TabBarView(children: [
            _ReceiptTab(
              selectedPaymentId: _selectedPaymentId,
              onSelect: (id) => setState(() => _selectedPaymentId = id),
            ),
            _CertificateTab(
              selectedStudentId: _selectedStudentId,
              onSelect: (id) => setState(() => _selectedStudentId = id),
            ),
          ])),
        ],
      ),
    );
  }
}

class _ReceiptTab extends ConsumerWidget {
  final String? selectedPaymentId;
  final ValueChanged<String?> onSelect;
  const _ReceiptTab({required this.selectedPaymentId, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(currentUserScopeProvider).valueOrNull?.scope;
    final payments = ref.watch(paymentsProvider).valueOrNull ?? [];
    final students = {for (final s in (ref.watch(studentsProvider).valueOrNull ?? <Student>[])) s.id: s};
    final fees = {for (final f in (ref.watch(feeTypesProvider).valueOrNull ?? <FeeType>[])) f.id: f};
    final school = ref.watch(schoolSettingProvider).valueOrNull;
    final visiblePayments = (scope == 'restricted')
        ? payments.where((p) => students.containsKey(p.studentId)).toList()
        : payments;
    final selected = visiblePayments.where((p) => p.id == selectedPaymentId).firstOrNull;

    return Row(children: [
      SizedBox(width: 360, child: ListView(children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('Sélectionnez un paiement pour prévisualiser/imprimer le reçu')),
        for (final p in visiblePayments)
          if (students[p.studentId] != null)
            ListTile(
              selected: p.id == selectedPaymentId,
              title: Text(p.receiptNumber),
              subtitle: Text('${students[p.studentId]!.lastName} ${students[p.studentId]!.firstName}'),
              onTap: () => onSelect(p.id),
            ),
        if (visiblePayments.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Aucun paiement disponible (ou hors de votre portée).')),
      ])),
      const VerticalDivider(width: 1),
      Expanded(child: selected == null || students[selected.studentId] == null
          ? const Center(child: Text('Aucun reçu sélectionné.'))
          : PdfPreview(
              build: (format) => ref.read(documentServiceProvider).buildPaymentReceipt(
                payment: selected,
                student: students[selected.studentId]!,
                feeType: fees[selected.feeTypeId],
                school: school,
              ),
              canChangeOrientation: false,
              canChangePageFormat: false,
            )),
    ]);
  }
}

class _CertificateTab extends ConsumerWidget {
  final String? selectedStudentId;
  final ValueChanged<String?> onSelect;
  const _CertificateTab({required this.selectedStudentId, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final students = ref.watch(studentsProvider).valueOrNull ?? [];
    final school = ref.watch(schoolSettingProvider).valueOrNull;
    final selected = students.where((s) => s.id == selectedStudentId).firstOrNull;

    return Row(children: [
      SizedBox(width: 360, child: ListView(children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('Sélectionnez un élève pour générer un certificat de scolarité')),
        for (final s in students)
          ListTile(
            selected: s.id == selectedStudentId,
            title: Text('${s.lastName} ${s.firstName}'),
            subtitle: Text(s.matricule),
            onTap: () => onSelect(s.id),
          ),
        if (students.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Aucun élève disponible (ou hors de votre portée).')),
      ])),
      const VerticalDivider(width: 1),
      Expanded(child: selected == null
          ? const Center(child: Text('Aucun élève sélectionné.'))
          : PdfPreview(
              build: (format) => ref.read(documentServiceProvider).buildStudentCertificate(
                student: selected,
                school: school,
              ),
              canChangeOrientation: false,
              canChangePageFormat: false,
            )),
    ]);
  }
}
