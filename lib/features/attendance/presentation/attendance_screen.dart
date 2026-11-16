import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/features/attendance/application/attendance_providers.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/students/application/students_providers.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  String? _classId;
  DateTime? _date;

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesProvider);
    final listAsync = ref.watch(attendanceListProvider((classId: _classId, date: _date)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Présences & Discipline'),
        actions: [
          FilledButton.icon(onPressed: () async {
            if (_classId == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sélectionnez une classe pour faire l\'appel'))); return; }
            final auth = ref.read(authControllerProvider);
            final repo = ref.read(attendanceRepositoryProvider);
            final students = await ref.read(studentsRepositoryProvider).list(actorUserId: auth.userId, classId: _classId, limit: 500);
            if (!context.mounted) return;
            String status = 'Présent';
            String? pickedStudent = students.isNotEmpty ? students.first.id : null;
            final ok = await showDialog<bool>(context: context, builder: (ctx)=>AlertDialog(
              title: const Text('Saisie rapide appel / événement'),
              content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(value: pickedStudent, decoration: const InputDecoration(labelText: 'Élève'), items: students.map((s)=>DropdownMenuItem(value: s.id, child: Text('${s.matricule} ${s.fullName}'))).toList(), onChanged: (v)=>pickedStudent=v),
                DropdownButtonFormField<String>(value: status, decoration: const InputDecoration(labelText: 'Statut'), items: const ['Présent','Absent','Retard','Incident'].map((s)=>DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v)=>status=v??'Présent'),
              ])),
              actions: [TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Annuler')), FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Enregistrer'))],
            ));
            if (ok == true && pickedStudent != null) {
              try {
                await repo.record(studentId: pickedStudent!, classId: _classId, date: DateTime.now(), status: status, actorUserId: auth.userId, actorUsername: auth.username);
                ref.invalidate(attendanceListProvider);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Présence/événement enregistré')));
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
              }
            }
          }, icon: const Icon(Icons.playlist_add_check), label: const Text('Saisie rapide')),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 260,
                  child: classesAsync.when(
                    data: (classes) {
                      final list = classes ?? const [];
                      return DropdownButtonFormField<String?>(
                        initialValue: _classId,
                        decoration: const InputDecoration(labelText: 'Classe'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Toutes')),
                          ...list.map((c) => DropdownMenuItem(value: c.id, child: Text(c.label))),
                        ],
                        onChanged: (v) => setState(() => _classId = v),
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Erreur: $e'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  icon: const Icon(Icons.date_range),
                  label: Text(_date == null ? 'Date (toutes)' : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}'),
                ),
                if (_date != null)
                  IconButton(onPressed: () => setState(() => _date = null), icon: const Icon(Icons.clear)),
                const Spacer(),
                const Chip(label: Text('Module MVP en cours')),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: listAsync.when(
                data: (rows) => Card(
                  child: rows.isEmpty
                      ? const Center(child: Text('Aucun événement de présence/discipline (données de test disponibles après import).'))
                      : SingleChildScrollView(
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Date')),
                              DataColumn(label: Text('Matricule')),
                              DataColumn(label: Text('Élève')),
                              DataColumn(label: Text('Classe')),
                              DataColumn(label: Text('Catégorie')),
                              DataColumn(label: Text('Statut')),
                              DataColumn(label: Text('Créneau/Faits')),
                              DataColumn(label: Text('Justification')),
                            ],
                            rows: rows.map((r) => DataRow(cells: [
                              DataCell(Text('${r.date.year}-${r.date.month.toString().padLeft(2, '0')}-${r.date.day.toString().padLeft(2, '0')}')),
                              DataCell(Text(r.matricule)),
                              DataCell(Text(r.studentName)),
                              DataCell(Text(r.classLabel ?? '-')),
                              DataCell(Text(r.category)),
                              DataCell(Text(r.status)),
                              DataCell(Text(r.slot ?? '-')),
                              DataCell(Text(r.justification ?? r.details ?? '-')),
                            ])).toList(),
                          ),
                        ),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erreur: $e\n(Vérifiez permission attendance.read)')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
