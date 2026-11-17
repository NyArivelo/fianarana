import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import 'package:fianarana/core/widgets/app_ui.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/documents/application/document_providers.dart';
import 'package:fianarana/features/documents/services/document_studio_pdf_service.dart';

const _docTypes = <String, String>{
  'bulletin': 'Bulletin / relevé',
  'certificat': 'Certificat / attestation de sortie',
  'recu': 'Reçu / paiement',
  'facture': 'Facture',
  'carte': 'Carte scolaire',
  'attestation': 'Attestation',
};

class DocumentStudioScreen extends ConsumerStatefulWidget {
  const DocumentStudioScreen({super.key});

  @override
  ConsumerState<DocumentStudioScreen> createState() => _DocumentStudioScreenState();
}

class _DocumentStudioScreenState extends ConsumerState<DocumentStudioScreen> {
  String _filterType = 'Tous';
  final _pdf = DocumentStudioPdfService();

  Future<void> _openEditor({dynamic tpl}) async {
    final auth = ref.read(authControllerProvider);
    final repo = ref.read(documentRepositoryProvider);
    final nameCtrl = TextEditingController(text: tpl?.name ?? '');
    String docType = tpl?.docType ?? 'bulletin';
    String pageFormat = tpl?.pageFormat ?? 'A4';
    bool isDefault = tpl?.isDefault ?? false;
    bool isActive = tpl?.isActive ?? true;
    Map<String, dynamic> content = {};
    try {
      if (tpl != null) content = jsonDecode(tpl.contentJson as String) as Map<String, dynamic>;
    } catch (_) {}
    final titleCtrl = TextEditingController(text: (content['title'] ?? '').toString());
    final headerCtrl = TextEditingController(text: (content['header'] ?? '').toString());
    final introCtrl = TextEditingController(text: (content['intro'] ?? '').toString());
    final bodyCtrl = TextEditingController(text: (content['body'] ?? '').toString());
    final footerCtrl = TextEditingController(text: (content['footer'] ?? '').toString());

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: Text(tpl == null ? 'Nouveau modèle (Document Studio)' : 'Modifier le modèle'),
        content: SizedBox(width: 760, height: 560, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom du modèle'))),
            const SizedBox(width: 8),
            SizedBox(width: 220, child: DropdownButtonFormField<String>(value: docType, decoration: const InputDecoration(labelText: 'Type'), items: _docTypes.entries.map((e)=>DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: (v)=>setD(()=>docType=v??'bulletin'))),
            const SizedBox(width: 8),
            SizedBox(width: 120, child: DropdownButtonFormField<String>(value: pageFormat, decoration: const InputDecoration(labelText: 'Format'), items: const ['A4','A5'].map((f)=>DropdownMenuItem(value:f, child: Text(f))).toList(), onChanged: (v)=>setD(()=>pageFormat=v??'A4'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Checkbox(value: isDefault, onChanged: (v)=>setD(()=>isDefault=v??false)),
            const Text('Modèle par défaut du type'),
            const SizedBox(width: 12),
            Checkbox(value: isActive, onChanged: (v)=>setD(()=>isActive=v??true)),
            const Text('Actif'),
          ]),
          const SizedBox(height: 6),
          const Text('Contenu configurable (placeholders {{eleve.nom}}, {{etablissement.nom}}, {{date.jour}}, etc. et formules sûres {{calc:...}} sans eval)', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          const SizedBox(height: 6),
          TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Titre')),
          TextField(controller: headerCtrl, decoration: const InputDecoration(labelText: 'En-tête'), maxLines: 2),
          TextField(controller: introCtrl, decoration: const InputDecoration(labelText: 'Introduction / identité'), maxLines: 3),
          TextField(controller: bodyCtrl, decoration: const InputDecoration(labelText: 'Corps du document'), maxLines: 6),
          TextField(controller: footerCtrl, decoration: const InputDecoration(labelText: 'Pied de page / mentions'), maxLines: 2),
        ]))),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Fermer')),
          OutlinedButton.icon(onPressed: () async {
            final c = {'title': titleCtrl.text, 'header': headerCtrl.text, 'intro': introCtrl.text, 'body': bodyCtrl.text, 'footer': footerCtrl.text};
            final bytes = await _pdf.renderTemplate(templateContent: c, context: _pdf.sampleContext(docType: docType), pageFormat: pageFormat);
            await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'apercu_modele.pdf');
          }, icon: const Icon(Icons.visibility_outlined, size: 16), label: const Text('Prévisualiser / Imprimer')),
          FilledButton.icon(onPressed: () async {
            try {
              await repo.upsertTemplate(
                id: tpl?.id,
                name: nameCtrl.text.trim().isEmpty ? 'Modèle' : nameCtrl.text.trim(),
                docType: docType,
                pageFormat: pageFormat,
                content: {'title': titleCtrl.text, 'header': headerCtrl.text, 'intro': introCtrl.text, 'body': bodyCtrl.text, 'footer': footerCtrl.text},
                description: 'Modèle Document Studio',
                isDefault: isDefault,
                isActive: isActive,
                actorUserId: auth.userId,
                actorUsername: auth.username,
              );
              ref.invalidate(documentTemplatesProvider);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modèle enregistré.')));
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
            }
          }, icon: const Icon(Icons.save_outlined, size: 16), label: const Text('Enregistrer')),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(documentTemplatesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Document Studio'),
        actions: [
          FilledButton.icon(onPressed: ()=>_openEditor(), icon: const Icon(Icons.add, size: 16), label: const Text('Nouveau modèle')),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: isDark ? const Color(0xFF0F172A) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
            child: Row(children: [
              const Icon(Icons.auto_awesome_mosaic_outlined, color: Color(0xFF2563EB)),
              const SizedBox(width: 10),
              const Expanded(child: Text('Modèles configurables (bulletins, certificats, reçus, factures, cartes, attestations), placeholders {{...}} et formules sûres {{calc:...}} sans eval, prévisualisation/impression PDF.', style: TextStyle(fontSize: 12))),
              const SizedBox(width: 12),
              SizedBox(width: 220, child: DropdownButtonFormField<String>(value: _filterType, decoration: const InputDecoration(labelText: 'Filtrer par type'), items: ['Tous', ..._docTypes.keys].map((k)=>DropdownMenuItem(value:k, child: Text(k=='Tous'?'Tous les types':(_docTypes[k]??k)))).toList(), onChanged: (v)=>setState(()=>_filterType=v??'Tous'))),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(child: listAsync.when(
            data: (items) {
              final list = _filterType=='Tous' ? items : items.where((t)=> (t as dynamic).docType==_filterType).toList();
              if (list.isEmpty) return const Center(child: Text('Aucun modèle. Créez ou réimportez les modèles par défaut.'));
              return ListView.builder(itemCount: list.length, itemBuilder: (c,i){
                final t = list[i] as dynamic;
                final typeLabel = _docTypes[t.docType] ?? t.docType;
                return Card(child: ListTile(
                  leading: CircleAvatar(backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.12), child: const Icon(Icons.description_outlined, color: Color(0xFF2563EB))),
                  title: Text(t.name as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('$typeLabel • Format ${t.pageFormat}${t.isDefault==true?' • Par défaut':''}${t.isActive==true?'':' • Inactif'}', style: const TextStyle(fontSize: 11)),
                  trailing: Wrap(spacing: 6, children: [
                    IconButton(tooltip: 'Prévisualiser', onPressed: () async {
                      try {
                        final content = jsonDecode(t.contentJson as String) as Map<String, dynamic>;
                        final bytes = await _pdf.renderTemplate(templateContent: content, context: _pdf.sampleContext(docType: t.docType as String), pageFormat: t.pageFormat as String);
                        await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'apercu_${t.docType}.pdf');
                      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur aperçu: $e'))); }
                    }, icon: const Icon(Icons.visibility_outlined)),
                    IconButton(tooltip: 'Modifier', onPressed: ()=>_openEditor(tpl: t), icon: const Icon(Icons.edit_outlined)),
                  ]),
                  onTap: ()=>_openEditor(tpl: t),
                ));
              });
            },
            loading: ()=>const Center(child: CircularProgressIndicator()),
            error: (e,_)=>Center(child: Text('Erreur: $e')),
          )),
        ]),
      ),
    );
  }
}
