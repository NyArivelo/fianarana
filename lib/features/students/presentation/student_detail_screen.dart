import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fianarana/features/students/application/students_providers.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';

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
    _medical.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final auth = ref.read(authControllerProvider);
      final repo = ref.read(studentsRepositoryProvider);
      await repo.createStudent(
        matricule: _matricule.text.trim(),
        lastName: _lastName.text.trim(),
        firstName: _firstName.text.trim(),
        sex: _sex,
        birthDate: _birthDate,
        birthPlace: _birthPlace.text.trim().isEmpty ? null : _birthPlace.text.trim(),
        classId: _classId,
        medicalNotes: _medical.text.trim().isEmpty ? null : _medical.text.trim(),
        actorUserId: auth.userId,
        actorUsername: auth.username,
      );
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
                            SizedBox(width: 220, child: TextFormField(controller: _matricule, decoration: const InputDecoration(labelText: 'Matricule *'), validator: (v) => v==null||v.trim().isEmpty?'Requis':null, enabled: isNew)),
                            SizedBox(width: 260, child: TextFormField(controller: _lastName, decoration: const InputDecoration(labelText: 'Nom *'), validator: (v) => v==null||v.trim().isEmpty?'Requis':null, enabled: isNew)),
                            SizedBox(width: 260, child: TextFormField(controller: _firstName, decoration: const InputDecoration(labelText: 'Prénom *'), validator: (v) => v==null||v.trim().isEmpty?'Requis':null, enabled: isNew)),
                            SizedBox(width: 140, child: DropdownButtonFormField<String>(value: _sex, decoration: const InputDecoration(labelText: 'Sexe'), items: const [
                              DropdownMenuItem(value: 'M', child: Text('M')),
                              DropdownMenuItem(value: 'F', child: Text('F')),
                            ], onChanged: isNew ? (v)=>setState(()=>_sex=v) : null)),
                            SizedBox(width: 260, child: TextFormField(controller: _birthPlace, decoration: const InputDecoration(labelText: 'Lieu de naissance'), enabled: isNew)),
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
                          TextFormField(controller: _medical, decoration: const InputDecoration(labelText: 'Observations médicales / suivi'), maxLines: 2, enabled: isNew),
                          const SizedBox(height: 16),
                          if (isNew)
                            FilledButton.icon(
                              onPressed: _saving ? null : _save,
                              icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                              label: const Text('Enregistrer l\'élève'),
                            )
                          else
                            const Text('Consultation du dossier (édition complète et transfert/quitus à enrichir).'),
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
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                        Text('Transfert / Radiation (procédure)'),
                        SizedBox(height: 8),
                        Text('• Quitus financier requis (scolarité/frais régularisés)\n• Quitus bibliothèque requis (aucun ouvrage en cours)\n• Génération certificat de sortie (Document Studio à implémenter)\n• Statut passé à "Transféré/Radiation" avec historique conservé'),
                        SizedBox(height: 8),
                        Text('Action de validation à finaliser dans le service métier (contrôles complets + PDF).'),
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
}
