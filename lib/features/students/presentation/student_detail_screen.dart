import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/documents/application/document_providers.dart';
import 'package:fianarana/features/documents/services/document_studio_pdf_service.dart';
import 'package:fianarana/features/students/application/students_providers.dart';
import 'package:fianarana/features/students/services/certificate_service.dart';

class StudentDetailScreen extends ConsumerStatefulWidget {
  final String? studentId; // null => création
  const StudentDetailScreen({super.key, this.studentId});

  @override
  ConsumerState<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends ConsumerState<StudentDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _matricule = TextEditingController();
  final _lastName = TextEditingController();
  final _firstName = TextEditingController();
  final _birthPlace = TextEditingController();
  final _birthCert = TextEditingController();
  final _nationalId = TextEditingController();
  final _medical = TextEditingController();
  String? _sex;
  String? _classId;
  DateTime? _birthDate;
  bool _saving = false;

  bool get isNew => widget.studentId == null || widget.studentId == 'new';

  @override
  void dispose() {
    _matricule.dispose();
    _lastName.dispose();
    _firstName.dispose();
    _birthPlace.dispose();
    _birthCert.dispose();
    _nationalId.dispose();
    _medical.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final auth = ref.read(authControllerProvider);
      final repo = ref.read(studentsRepositoryProvider);
      if (isNew) {
        await repo.createStudent(
          matricule: _matricule.text.trim(),
          lastName: _lastName.text.trim(),
          firstName: _firstName.text.trim(),
          sex: _sex,
          birthDate: _birthDate,
          birthPlace: _birthPlace.text.trim().isEmpty ? null : _birthPlace.text.trim(),
          birthCertificateNumber: _birthCert.text.trim().isEmpty ? null : _birthCert.text.trim(),
          nationalIdNumber: _nationalId.text.trim().isEmpty ? null : _nationalId.text.trim(),
          classId: _classId,
          medicalNotes: _medical.text.trim().isEmpty ? null : _medical.text.trim(),
          actorUserId: auth.userId,
          actorUsername: auth.username,
        );
      } else {
        await repo.updateStudent(
          studentId: widget.studentId!,
          matricule: _matricule.text.trim(),
          lastName: _lastName.text.trim(),
          firstName: _firstName.text.trim(),
          sex: _sex,
          birthDate: _birthDate,
          birthPlace: _birthPlace.text.trim().isEmpty ? null : _birthPlace.text.trim(),
          birthCertificateNumber: _birthCert.text.trim().isEmpty ? null : _birthCert.text.trim(),
          nationalIdNumber: _nationalId.text.trim().isEmpty ? null : _nationalId.text.trim(),
          medicalNotes: _medical.text.trim().isEmpty ? null : _medical.text.trim(),
          actorUserId: auth.userId,
          actorUsername: auth.username,
        );
      }
      ref.invalidate(studentsListProvider);
      ref.invalidate(studentDetailProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Élève enregistré')));
        context.go('/students');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesProvider);
    final detailAsync = !isNew ? ref.watch(studentDetailProvider(widget.studentId!)) : const AsyncValue.data(null);
    final enrollmentsAsync = !isNew ? ref.watch(studentEnrollmentsProvider(widget.studentId!)) : const AsyncValue.data(<dynamic>[]);
    final guardiansAsync = !isNew ? ref.watch(studentGuardiansProvider(widget.studentId!)) : const AsyncValue.data(<dynamic>[]);

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Nouvel élève' : 'Dossier élève'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/students')),
        actions: [
          if (!isNew)
            PopupMenuButton<String>(
              tooltip: 'Générer un document (modèle)',
              icon: const Icon(Icons.description_outlined),
              onSelected: (t) => _generateFromTemplate(student, t),
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'attestation', child: Text('Attestation de scolarité')),
                PopupMenuItem(value: 'carte', child: Text('Carte scolaire')),
                PopupMenuItem(value: 'certificat', child: Text('Certificat / attestation (modèle)')),
                PopupMenuItem(value: 'bulletin', child: Text('Bulletin (modèle générique)')),
              ],
            ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (student) {
          if (!isNew && student != null && _matricule.text.isEmpty) {
            _matricule.text = student.matricule;
            _lastName.text = student.lastName;
            _firstName.text = student.firstName;
            _birthPlace.text = student.birthPlace ?? '';
            _birthCert.text = (student as dynamic).birthCertificateNumber ?? '';
            _nationalId.text = (student as dynamic).nationalIdNumber ?? '';
            _medical.text = student.medicalNotes ?? '';
            _sex = student.sex;
            _birthDate = student.birthDate;
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isNew ? 'Inscription / création de dossier' : 'Informations élève', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          Wrap(spacing: 12, runSpacing: 12, children: [
                            SizedBox(width: 220, child: TextFormField(controller: _matricule, decoration: const InputDecoration(labelText: 'Matricule *'), validator: (v) => v==null||v.trim().isEmpty?'Requis':null)),
                            SizedBox(width: 260, child: TextFormField(controller: _lastName, decoration: const InputDecoration(labelText: 'Nom *'), validator: (v) => v==null||v.trim().isEmpty?'Requis':null)),
                            SizedBox(width: 260, child: TextFormField(controller: _firstName, decoration: const InputDecoration(labelText: 'Prénom *'), validator: (v) => v==null||v.trim().isEmpty?'Requis':null)),
                            SizedBox(width: 140, child: DropdownButtonFormField<String>(value: _sex, decoration: const InputDecoration(labelText: 'Sexe'), items: const [
                              DropdownMenuItem(value: 'M', child: Text('M')),
                              DropdownMenuItem(value: 'F', child: Text('F')),
                            ], onChanged: (v)=>setState(()=>_sex=v))),
                            SizedBox(width: 220, child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(context: context, initialDate: _birthDate ?? DateTime(2012,1,1), firstDate: DateTime(1990), lastDate: DateTime.now());
                                if (picked != null) setState(()=>_birthDate = picked);
                              },
                              icon: const Icon(Icons.cake_outlined, size: 16),
                              label: Text(_birthDate == null ? 'Date de naissance' : '${_birthDate!.day.toString().padLeft(2,'0')}/${_birthDate!.month.toString().padLeft(2,'0')}/${_birthDate!.year}'),
                            )),
                            SizedBox(width: 260, child: TextFormField(controller: _birthPlace, decoration: const InputDecoration(labelText: 'Lieu de naissance'))),
                            SizedBox(width: 260, child: TextFormField(controller: _birthCert, decoration: const InputDecoration(labelText: 'N° acte de naissance (état civil)'))),
                            SizedBox(width: 260, child: TextFormField(controller: _nationalId, decoration: const InputDecoration(labelText: 'N° identification nationale / CIN'))),
                          ]),
                          const SizedBox(height: 12),
                          classesAsync.when(
                            data: (classes) => SizedBox(
                              width: 320,
                              child: DropdownButtonFormField<String?>(
                                value: _classId,
                                decoration: const InputDecoration(labelText: 'Classe (inscription)'),
                                items: [
                                  const DropdownMenuItem<String?>(value: null, child: Text('Non assignée')),
                                  ...classes.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.label))),
                                ],
                                onChanged: isNew ? (v) => setState(() => _classId = v) : null,
                              ),
                            ),
                            loading: () => const LinearProgressIndicator(),
                            error: (e, _) => Text('Erreur classes: $e'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(controller: _medical, decoration: const InputDecoration(labelText: 'Observations médicales / suivi'), maxLines: 2),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                            label: Text(isNew ? 'Enregistrer l\'élève' : 'Enregistrer les modifications'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!isNew) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Inscriptions', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        enrollmentsAsync.when(
                          data: (list) => list.isEmpty ? const Text('Aucune inscription') : Column(
                            children: list.map<Widget>((e) => ListTile(
                              leading: const Icon(Icons.assignment_ind_outlined),
                              title: Text('Statut: ${(e as dynamic).status}'),
                              subtitle: Text('Quitus finance: ${(e as dynamic).financeClearance} | Quitus bibliothèque: ${(e as dynamic).libraryClearance}'),
                            )).toList(),
                          ),
                          loading: () => const LinearProgressIndicator(),
                          error: (e, _) => Text('Erreur: $e'),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Responsables légaux', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        guardiansAsync.when(
                          data: (list) => list.isEmpty ? const Text('Aucun responsable lié') : Column(
                            children: list.map<Widget>((g) {
                              final gd = g as dynamic;
                              return ListTile(
                                leading: const Icon(Icons.family_restroom),
                                title: Text('${gd.lastName} ${gd.firstName}'),
                                subtitle: Text('${gd.relationship ?? ''} • ${gd.phone ?? ''} • ${gd.email ?? ''}'),
                              );
                            }).toList(),
                          ),
                          loading: () => const LinearProgressIndicator(),
                          error: (e, _) => Text('Erreur: $e'),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('Transfert / Radiation (procédure)', style: Theme.of(context).textTheme.titleMedium)),
                          FilledButton.icon(
                            onPressed: () => _openTransferDialog(student, enrollmentsAsync.valueOrNull ?? const []),
                            icon: const Icon(Icons.exit_to_app, size: 16),
                            label: const Text('Procéder'),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        const Text('• Quitus financier requis (scolarité/frais régularisés)\n• Quitus bibliothèque requis (aucun ouvrage en cours)\n• Génération du certificat de sortie (PDF)\n• Statut passé à "Transféré/Radiation" avec historique conservé'),
                      ]),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _generateFromTemplate(dynamic student, String docType) async {
    if (student == null) return;
    try {
      final auth = ref.read(authControllerProvider);
      final docRepo = ref.read(documentRepositoryProvider);
      final tpl = await docRepo.defaultTemplate(docType, actorUserId: auth.userId);
      if (tpl == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Aucun modèle actif trouvé pour "$docType". Créez-en un dans Document Studio.')));
        return;
      }
      final overview = await ref.read(studentsRepositoryProvider).overview(student.id as String, actorUserId: auth.userId);
      final content = jsonDecode(tpl.contentJson as String) as Map<String, dynamic>;
      final pdf = DocumentStudioPdfService();
      final now = DateTime.now();
      final ctx = <String, dynamic>{
        'etablissement': {'nom': 'Établissement scolaire', 'adresse': ''},
        'eleve': {
          'nom': '${student.lastName} ${student.firstName}',
          'matricule': student.matricule,
          'classe': overview.classLabel ?? '',
          'sexe': student.sex ?? '',
          'date_naissance': student.birthDate == null ? '' : '${(student.birthDate as DateTime).day.toString().padLeft(2,'0')}/${(student.birthDate as DateTime).month.toString().padLeft(2,'0')}/${(student.birthDate as DateTime).year}',
          'lieu_naissance': student.birthPlace ?? '',
        },
        'annee': {'libelle': '2026-2027'},
        'periode': {'libelle': ''},
        'date': {'jour': '${now.day.toString().padLeft(2,'0')}/${now.month.toString().padLeft(2,'0')}/${now.year}'},
        'resultats': {'moyenne': '', 'rang': '', 'mention': '', 'appreciation': ''},
      };
      final bytes = await pdf.renderTemplate(templateContent: content, context: ctx, pageFormat: tpl.pageFormat);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${docType}_${student.matricule}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur génération document: $e')));
    }
  }

  Future<void> _openTransferDialog(dynamic student, List<dynamic> enrollments) async {
    if (student == null || enrollments.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aucune inscription trouvée pour cet élève.')));
      }
      return;
    }
    final enrollment = enrollments.first as dynamic;
    final reasonCtrl = TextEditingController(text: 'Transfert vers un autre établissement');
    bool finance = enrollment.financeClearance == true;
    bool library = enrollment.libraryClearance == true;
    final auth = ref.read(authControllerProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Transfert / Radiation'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Validez les quitus requis avant de générer le certificat et de clôturer le dossier.'),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: finance,
                  onChanged: (v) => setD(() => finance = v ?? false),
                  title: const Text('Quitus financier validé'),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
                CheckboxListTile(
                  value: library,
                  onChanged: (v) => setD(() => library = v ?? false),
                  title: const Text('Quitus bibliothèque validé'),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(labelText: 'Motif de sortie / radiation'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('Valider & générer certificat'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final repo = ref.read(studentsRepositoryProvider);
      await repo.transferStudent(
        studentId: student.id as String,
        enrollmentId: enrollment.id as String,
        reason: reasonCtrl.text.trim().isEmpty ? 'Transfert/Radiation' : reasonCtrl.text.trim(),
        financeClearance: finance,
        libraryClearance: library,
        actorUserId: auth.userId,
        actorUsername: auth.username,
      );
      final now = DateTime.now();
      final overview = await repo.overview(student.id as String, actorUserId: auth.userId);
      final cert = await CertificateService().generateExitCertificate(
        ExitCertificateData(
          studentName: '${student.lastName} ${student.firstName}',
          matricule: student.matricule as String,
          classLabel: overview.classLabel,
          birthDate: student.birthDate as DateTime?,
          birthPlace: student.birthPlace as String?,
          exitDate: now,
          reason: reasonCtrl.text.trim().isEmpty ? 'Transfert/Radiation' : reasonCtrl.text.trim(),
          schoolYearLabel: '2026-2027',
          financeClearance: finance,
          libraryClearance: library,
        ),
        establishmentName: 'Établissement scolaire',
      );
      await Printing.layoutPdf(onLayout: (_) async => cert, name: 'certificat_sortie_${student.matricule}.pdf');
      ref.invalidate(studentsListProvider);
      ref.invalidate(studentDetailProvider);
      ref.invalidate(studentEnrollmentsProvider(student.id as String));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Transfert/radiation enregistré et certificat de sortie généré.')));
        context.go('/students');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur transfert/certificat : $e')));
      }
    }
  }
}
