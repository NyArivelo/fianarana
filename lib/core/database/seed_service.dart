import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Service utilitaire pour charger les données de test fournies (assets/seed/*.json)
/// issues de `donnees_de_test.xlsx`.
///
/// À utiliser lors de l'initialisation, de l'assistant de première installation
/// ou du mode bac à sable pour pré-remplir la base.
class SeedService {
  static const seedFiles = <String, String>{
    'establishment': 'assets/seed/param_tres__tablissement.json',
    'users_roles': 'assets/seed/utilisateurs_r_les.json',
    'classes_subjects': 'assets/seed/classes_mati_res.json',
    'staff': 'assets/seed/personnel_enseignants.json',
    'guardians': 'assets/seed/responsables_l_gaux.json',
    'students_enrollments': 'assets/seed/_l_ves_inscriptions.json',
    'evaluations': 'assets/seed/_valuations_notes.json',
    'attendance_discipline': 'assets/seed/pr_sences_discipline.json',
    'finance': 'assets/seed/finances_paiements.json',
    'library_facilities': 'assets/seed/biblioth_que_locaux.json',
    'audit': 'assets/seed/journal_audit.json',
  };

  Future<List<Map<String, dynamic>>> load(String key) async {
    final path = seedFiles[key];
    if (path == null) {
      throw ArgumentError('Clé de seed inconnue: $key');
    }
    final raw = await rootBundle.loadString(path);
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded.cast<Map>().map((e) => e.map((k, v) => MapEntry(k.toString(), v))).toList();
  }

  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in seedFiles.entries) {
      result[entry.key] = await load(entry.key);
    }
    return result;
  }
}
