import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/features/attendance/application/attendance_providers.dart';
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
      appBar: AppBar(title: const Text('Présences & Discipline')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 260,
                  child: classesAsync.when(
                    data: (classes) => DropdownButtonFormField<String?>(
                      value: _classId,
                      decoration: const InputDecoration(labelText: 'Classe'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Toutes')),
                        ...classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.label))),
                      ],
                      onChanged: (v) => setState(() => _classId = v),
                    ),
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
                const Tooltip(
                  message: 'Saisie rapide de l’appel (grille clavier) à compléter',
                  child: Chip(label: Text('Module MVP en cours')),
                ),
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
