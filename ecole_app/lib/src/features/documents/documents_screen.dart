import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/database/app_database.dart';
import '../../core/security/current_user_scope.dart';
import '../../core/utils/safe_formula_engine.dart';
import '../finance/finance_providers.dart';
import '../settings/settings_providers.dart';
import '../students/students_providers.dart';
import 'document_service.dart';
import 'template_providers.dart';

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
      length: 3,
      child: Column(
        children: [
          const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Reçu de paiement'),
            Tab(text: 'Certificat de scolarité'),
            Tab(text: 'Studio / Modèles'),
          ]),
          Expanded(child: TabBarView(children: [
            _ReceiptTab(
              selectedPaymentId: _selectedPaymentId,
              onSelect: (id) => setState(() => _selectedPaymentId = id),
            ),
            _CertificateTab(
              selectedStudentId: _selectedStudentId,
              onSelect: (id) => setState(() => _selectedStudentId = id),
            ),
            const _TemplateStudioTab(),
          ])),
        ],
      ),
    );
  }
}

class _TemplateStudioTab extends ConsumerStatefulWidget {
  const _TemplateStudioTab();
  @override
  ConsumerState<_TemplateStudioTab> createState() => _TemplateStudioTabState();
}

class _TemplateStudioTabState extends ConsumerState<_TemplateStudioTab> {
  String? _selectedTemplateId;
  String? _studentId;
  String? _paymentId;
  String _previewText = '';

  static const _defaultBody = '''Objet: {{document_title|Document}}

Je soussigné(e), direction de {{school_name}}, certifie que {{student_full_name}} (matricule: {{student_matricule}}) est concerné(e) par le présent document.

Montant de référence: {{amount|0}}
Remise appliquée: {{discount|0}}
Montant net (formule sécurisée): ={{ amount - discount }}

Fait le {{date}}.''';

  Map<String, Object?> _buildContext(WidgetRef ref) {
    final school = ref.read(schoolSettingProvider).valueOrNull;
    final students = {for (final s in (ref.read(studentsProvider).valueOrNull ?? <Student>[])) s.id: s};
    final paymentsList = ref.read(paymentsProvider).valueOrNull ?? <Payment>[];
    final payments = {for (final p in paymentsList) p.id: p};
    final adjustments = ref.read(adjustmentsProvider).valueOrNull ?? <FinancialAdjustment>[];
    final enrollments = _studentId == null ? <Enrollment>[] : (ref.read(enrollmentsProvider(_studentId!)).valueOrNull ?? <Enrollment>[]);
    final student = _studentId != null ? students[_studentId] : null;
    final payment = _paymentId != null ? payments[_paymentId] : null;
    final now = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final studentId = _studentId;
    final studentPays = studentId == null ? <Payment>[] : paymentsList.where((p)=>p.studentId==studentId && !p.isDeleted && p.status=='valid').toList();
    final studentAdjs = studentId == null ? <FinancialAdjustment>[] : adjustments.where((a)=>a.studentId==studentId && !a.isDeleted && a.status=='active').toList();
    final paidTotal = studentPays.fold<double>(0,(a,p)=>a+p.amount);
    final adjustmentsTotal = studentAdjs.fold<double>(0,(a,x)=>a+x.amount);
    final plans = studentId == null ? <PaymentPlan>[] : (ref.read(paymentPlansProvider(studentId)).valueOrNull ?? <PaymentPlan>[]);
    final plannedTotal = plans.where((p)=>!p.isDeleted).fold<double>(0,(a,p)=>a+p.totalAmount);
    final balance = plannedTotal - adjustmentsTotal - paidTotal;
    Enrollment? currentEnrollment;
    if (enrollments.isNotEmpty) {
      currentEnrollment = enrollments.firstWhere((e)=>e.status=='validee' || e.status=='active', orElse: ()=>enrollments.first);
    }
    // resolve class name if possible via available providers cache
    String className = '';
    try {
      // attempt to read classes for null/year - may be empty but safe
      // ignore: avoid_dynamic_calls
    } catch (_) {}
    if (currentEnrollment?.classId != null) {
      // best-effort: scan common provider states not trivial; keep id fallback
      className = currentEnrollment!.classId ?? '';
    }
    return <String, Object?>{
      'date': now,
      'school_name': school?.name ?? 'Établissement',
      'school_address': school?.address ?? '',
      'school_phone': school?.phone ?? '',
      'school_email': school?.email ?? '',
      'student_full_name': student == null ? '' : '${student.lastName} ${student.firstName}',
      'student_last_name': student?.lastName ?? '',
      'student_first_name': student?.firstName ?? '',
      'student_matricule': student?.matricule ?? '',
      'student_status': student?.status ?? '',
      'student_gender': student?.gender ?? '',
      'enrollment_status': currentEnrollment?.status ?? '',
      'class_id': currentEnrollment?.classId ?? '',
      'class_name': className,
      'receipt_number': payment?.receiptNumber ?? '',
      'amount': payment?.amount ?? 0,
      'discount': 0,
      'paid': payment?.amount ?? 0,
      'paid_total': paidTotal,
      'adjustments_total': adjustmentsTotal,
      'planned_total': plannedTotal,
      'balance_due': balance,
      'document_title': 'Document',
    };
  }

  void _refreshPreview(DocumentTemplate? t) {
    if (t == null) { setState(() => _previewText = ''); return; }
    final engine = const SafeFormulaEngine();
    final ctx = _buildContext(ref);
    ctx['document_title'] = t.title ?? t.name;
    setState(() => _previewText = engine.render(t.body, ctx));
  }

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(documentTemplatesProvider).valueOrNull ?? [];
    final selected = templates.where((t) => t.id == _selectedTemplateId).firstOrNull;
    final students = ref.watch(studentsProvider).valueOrNull ?? [];
    final scope = ref.watch(currentUserScopeProvider).valueOrNull?.scope;
    final allPayments = ref.watch(paymentsProvider).valueOrNull ?? [];
    final visibleStudentsMap = {for (final s in students) s.id: s};
    final payments = (scope == 'restricted')
        ? allPayments.where((p) => visibleStudentsMap.containsKey(p.studentId)).toList()
        : allPayments;
    final category = ref.watch(templateCategoryFilterProvider);
    if (selected != null && _previewText.isEmpty) _refreshPreview(selected);

    return Row(children: [
      SizedBox(width: 320, child: Column(children: [
        Padding(padding: const EdgeInsets.all(8), child: Row(children: [
          Expanded(child: DropdownButtonFormField<String>(initialValue: category, isDense: true, decoration: const InputDecoration(labelText: 'Catégorie'), items: const [
            DropdownMenuItem(value: 'all', child: Text('Toutes')),
            DropdownMenuItem(value: 'general', child: Text('Général')),
            DropdownMenuItem(value: 'receipt', child: Text('Reçu')),
            DropdownMenuItem(value: 'certificate', child: Text('Certificat')),
            DropdownMenuItem(value: 'letter', child: Text('Courrier')),
            DropdownMenuItem(value: 'invoice', child: Text('Facture')),
          ], onChanged: (v)=>ref.read(templateCategoryFilterProvider.notifier).state=v??'all')),
          IconButton(icon: const Icon(Icons.add), tooltip: 'Nouveau modèle', onPressed: ()=>_editTemplate(context, ref, null, _defaultBody)),
        ])),
        const Divider(height: 1),
        Expanded(child: templates.isEmpty ? const Center(child: Text('Aucun modèle. Créez-en un pour le studio documentaire.')) : ListView.builder(itemCount: templates.length, itemBuilder: (context,i){
          final t = templates[i];
          return ListTile(
            selected: t.id == _selectedTemplateId,
            title: Text(t.name),
            subtitle: Text('${t.category}${t.isActive ? '' : ' • inactif'}'),
            trailing: Wrap(spacing: 0, children: [
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: ()=>_editTemplate(context, ref, t, t.body)),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: ()=>ref.read(templateRepositoryProvider).deleteTemplate(t.id)),
            ]),
            onTap: () { setState(() { _selectedTemplateId = t.id; }); _refreshPreview(t); },
          );
        })),
      ])),
      const VerticalDivider(width: 1),
      Expanded(child: selected == null ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Sélectionnez ou créez un modèle.\nVariables: {{student_full_name}}, {{student_matricule}}, {{student_status}}, {{school_name}}, {{school_address}}, {{school_phone}}, {{school_email}}, {{enrollment_status}}, {{class_id}}, {{receipt_number}}, {{amount}}, {{paid_total}}, {{adjustments_total}}, {{planned_total}}, {{balance_due}}, {{date}}…\nFormules sécurisées (sans eval): ={{ planned_total - adjustments_total - paid_total }} ou ={{ amount - discount }}'))) : Column(children: [
        Padding(padding: const EdgeInsets.all(8), child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 260, child: DropdownButtonFormField<String?>(initialValue: _studentId, isDense: true, decoration: const InputDecoration(labelText: 'Contexte élève'), items: [const DropdownMenuItem(value: null, child: Text('(Aucun)')), for (final s in students) DropdownMenuItem(value: s.id, child: Text('${s.lastName} ${s.firstName}'))], onChanged: (v){ setState(()=>_studentId=v); _refreshPreview(selected); })),
          SizedBox(width: 260, child: DropdownButtonFormField<String?>(initialValue: _paymentId, isDense: true, decoration: const InputDecoration(labelText: 'Contexte paiement'), items: [const DropdownMenuItem(value: null, child: Text('(Aucun)')), for (final p in payments.take(100)) DropdownMenuItem(value: p.id, child: Text(p.receiptNumber))], onChanged: (v){ setState(()=>_paymentId=v); _refreshPreview(selected); })),
          OutlinedButton.icon(onPressed: ()=>_refreshPreview(selected), icon: const Icon(Icons.refresh), label: const Text('Rafraîchir aperçu')),
          FilledButton.icon(onPressed: () async {
            final school = ref.read(schoolSettingProvider).valueOrNull;
            final bytes = await ref.read(documentServiceProvider).buildFromTemplate(title: selected.title ?? selected.name, renderedBody: _previewText, school: school);
            if (!context.mounted) return;
            await showDialog(context: context, builder: (dctx)=>AlertDialog(title: Text('Aperçu PDF — ${selected.name}'), content: SizedBox(width: 700, height: 800, child: PdfPreview(build: (_)=>bytes, canChangeOrientation: false, canChangePageFormat: false)), actions: [TextButton(onPressed: ()=>Navigator.pop(dctx), child: const Text('Fermer'))]));
          }, icon: const Icon(Icons.picture_as_pdf), label: const Text('Générer PDF')),
        ])),
        const Divider(height: 1),
        Expanded(child: Row(children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Modèle (aperçu source)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Expanded(child: SingleChildScrollView(child: SelectableText(selected.body, style: const TextStyle(fontFamily: 'monospace')))),
          ]))),
          const VerticalDivider(width: 1),
          Expanded(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Rendu (placeholders + formules sécurisées)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Expanded(child: Container(width: double.infinity, padding: const EdgeInsets.all(12), color: Theme.of(context).colorScheme.surfaceContainerLow, child: SingleChildScrollView(child: SelectableText(_previewText.isEmpty ? '(vide)' : _previewText)))),
          ]))),
        ])),
      ])),
    ]);
  }

  static Future<void> _editTemplate(BuildContext context, WidgetRef ref, DocumentTemplate? t, String initialBody) async {
    final name = TextEditingController(text: t?.name ?? '');
    final title = TextEditingController(text: t?.title ?? '');
    final body = TextEditingController(text: initialBody);
    String category = t?.category ?? 'general';
    bool active = t?.isActive ?? true;
    await showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setState)=>AlertDialog(
      title: Text(t==null?'Nouveau modèle':'Modifier le modèle'),
      content: SizedBox(width: 720, height: 520, child: Column(children: [
        Row(children: [
          Expanded(child: TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom du modèle *'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: title, decoration: const InputDecoration(labelText: 'Titre document (PDF)'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(initialValue: category, decoration: const InputDecoration(labelText: 'Catégorie'), items: const [
            DropdownMenuItem(value: 'general', child: Text('Général')), DropdownMenuItem(value: 'receipt', child: Text('Reçu')),
            DropdownMenuItem(value: 'certificate', child: Text('Certificat')), DropdownMenuItem(value: 'letter', child: Text('Courrier')),
            DropdownMenuItem(value: 'invoice', child: Text('Facture')),
          ], onChanged: (v)=>setState(()=>category=v??'general'))),
          const SizedBox(width: 8),
          Expanded(child: CheckboxListTile(value: active, onChanged: (v)=>setState(()=>active=v??true), title: const Text('Actif'), controlAffinity: ListTileControlAffinity.leading)),
        ]),
        const SizedBox(height: 8),
        const Align(alignment: Alignment.centerLeft, child: Text('Corps du modèle — placeholders {{cle}} ou {{cle|defaut}}, formules sécurisées ={{ expression }} (ex: ={{ amount - discount }}). Aucun eval.', style: TextStyle(fontSize: 12))),
        const SizedBox(height: 4),
        Expanded(child: TextField(controller: body, maxLines: null, expands: true, decoration: const InputDecoration(border: OutlineInputBorder(), alignLabelWithHint: true), style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
      ])),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () async {
        if (name.text.trim().isEmpty || body.text.trim().isEmpty) return;
        await ref.read(templateRepositoryProvider).upsertTemplate(id: t?.id, name: name.text.trim(), category: category, title: title.text.trim().isEmpty?null:title.text.trim(), body: body.text, isActive: active);
        if (ctx.mounted) Navigator.pop(ctx);
      }, child: const Text('Enregistrer'))],
    )));
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
