import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'dart:convert';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/core/settings/app_config.dart';
import 'package:fianarana/core/widgets/app_ui.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/documents/application/document_providers.dart';
import 'package:fianarana/features/documents/services/document_studio_pdf_service.dart';
import 'package:fianarana/features/grades/application/council_providers.dart';
import 'package:fianarana/features/grades/application/grades_providers.dart';
import 'package:fianarana/features/grades/data/grades_repository.dart';
import 'package:fianarana/features/grades/services/bulletin_service.dart';
import 'package:fianarana/features/grades/services/grades_import_service.dart';
import 'package:fianarana/features/students/application/students_providers.dart';
import 'package:fianarana/features/timetable/application/timetable_providers.dart';

class GradesScreen extends ConsumerStatefulWidget {
  const GradesScreen({super.key});

  @override
  ConsumerState<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends ConsumerState<GradesScreen> {
  String? _classId;
  String? _subjectId;
  String _statusFilter = 'Tous';
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _generateBulletin(GradeRow row) async {
    final repo = ref.read(gradesRepositoryProvider);
    final auth = ref.read(authControllerProvider);
    final all = await ref.read(gradesListProvider((classId: _classId, subjectId: _subjectId)).future);
    final studentRows = all.where((g) => g.studentId == row.studentId).toList();
    final periodIds = studentRows.map((g)=>g.periodId).whereType<String>().toSet();
    final inferredPeriodId = periodIds.length == 1 ? periodIds.first : null;

    final snap = await repo.latestBulletinSnapshot(studentId: row.studentId, classId: row.classId ?? _classId, periodId: inferredPeriodId);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Bulletin'),
        children: [
          if (snap != null)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'print_snapshot'), child: ListTile(leading: const Icon(Icons.verified_outlined), title: const Text('Imprimer le bulletin publié (snapshot figé)'), subtitle: Text('Publié le ${snap.publishedAt.toLocal()}'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'standard'), child: const ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Générer PDF (données actuelles)'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'studio'), child: const ListTile(leading: Icon(Icons.auto_awesome_mosaic_outlined), title: Text('Générer via Document Studio (données actuelles)'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'publish'), child: const ListTile(leading: Icon(Icons.publish_outlined), title: Text('Publier / figer le bulletin (snapshot)'))),
        ],
      ),
    );
    if (choice == null) return;

    String mentionFor(double? a) {
      if (a == null) return '';
      if (a >= 16) return 'Très bien';
      if (a >= 14) return 'Bien';
      if (a >= 12) return 'Assez bien';
      if (a >= 10) return 'Passable';
      return 'Insuffisant';
    }

    Map<String, dynamic> buildSnapshot() {
      final avg = GradesRepository.weightedAverage(studentRows);
      final mention = mentionFor(avg);
      final subjects = studentRows.map((g)=> {
        'subject': g.subjectName ?? g.label,
        'score': g.score,
        'maxScore': g.maxScore,
        'coefficient': g.coefficient,
        'isExempt': g.isExempt,
        'masteryLevel': g.masteryLevel,
        'observation': g.observation,
        'label': g.label,
      }).toList();
      return {
        'student': {'id': row.studentId, 'name': row.studentName, 'matricule': row.matricule, 'classId': row.classId ?? _classId, 'classLabel': row.classLabel},
        'periodId': inferredPeriodId,
        'periodLabel': 'Période (filtre courant)',
        'subjects': subjects,
        'average': avg,
        'mention': mention.isEmpty ? null : mention,
        'generatedAt': DateTime.now().toIso8601String(),
        'establishmentName': 'Établissement scolaire',
      };
    }

    Future<void> renderStandard(Map<String, dynamic> data) async {
      final subs = (data['subjects'] as List).cast<dynamic>().map((m0){
        final m = (m0 as Map).cast<String,dynamic>();
        return BulletinSubjectLine(
          subject: (m['subject'] ?? '').toString(),
          score: (m['score'] as num?)?.toDouble(),
          maxScore: (m['maxScore'] as num?)?.toDouble() ?? 20,
          coefficient: (m['coefficient'] as num?)?.toDouble() ?? 1,
          isExempt: m['isExempt'] == true,
          masteryLevel: m['masteryLevel'] as String?,
          observation: m['observation'] as String?,
        );
      }).toList();
      final student = (data['student'] as Map).cast<String,dynamic>();
      final b = BulletinStudentData(
        fullName: (student['name'] ?? row.studentName).toString(),
        matricule: (student['matricule'] ?? row.matricule).toString(),
        classLabel: student['classLabel'] as String?,
        periodLabel: data['periodLabel'] as String?,
        subjects: subs,
        average: (data['average'] as num?)?.toDouble(),
        mention: data['mention'] as String?,
        councilDecision: data['councilDecision'] as String?,
        appreciation: data['appreciation'] as String?,
        rank: (data['rank'] as num?)?.toInt(),
      );
      final bytes = await BulletinService().generateStudentBulletin(b, establishmentName: (data['establishmentName'] ?? 'Établissement scolaire').toString());
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'bulletin_${row.matricule}.pdf');
    }

    if (choice == 'publish') {
      try {
        final data = buildSnapshot();
        await repo.publishBulletinSnapshot(studentId: row.studentId, classId: row.classId ?? _classId, periodId: inferredPeriodId, snapshot: data, actorUserId: auth.userId, actorUsername: auth.username);
        _snack('Bulletin publié et figé (snapshot). Les réimpressions utiliseront cette version.');
      } catch (e) { _snack('Erreur publication bulletin : $e'); }
      return;
    }

    if (choice == 'print_snapshot' && snap != null) {
      try {
        final data = jsonDecode(snap.snapshotJson) as Map<String, dynamic>;
        await renderStandard(data);
      } catch (e) { _snack('Erreur impression snapshot : $e'); }
      return;
    }

    final live = buildSnapshot();
    if (choice == 'studio') {
      try {
        final docRepo = ref.read(documentRepositoryProvider);
        final tpl = await docRepo.defaultTemplate('bulletin', actorUserId: auth.userId);
        if (tpl == null) { _snack('Aucun modèle "bulletin" actif trouvé dans Document Studio.'); return; }
        final content = jsonDecode(tpl.contentJson as String) as Map<String, dynamic>;
        final pdf = DocumentStudioPdfService();
        final subjects = (live['subjects'] as List).cast<dynamic>();
        final lines = subjects.map((g0){ final m=(g0 as Map).cast<String,dynamic>(); final sc=m['score']; final exempt=m['isExempt']==true; final ml=(m['masteryLevel']??'').toString(); return '- ${m['subject']}: ${exempt ? "Dispensé" : (sc!=null ? (sc as num).toDouble().toStringAsFixed(2) : "-")}${ml.isNotEmpty ? " ($ml)" : ""}'; }).join('\n');
        final now = DateTime.now();
        final student = (live['student'] as Map).cast<String,dynamic>();
        final ctx = <String, dynamic>{
          'etablissement': {'nom': live['establishmentName'] ?? 'Établissement scolaire', 'adresse': ''},
          'eleve': {'nom': student['name'] ?? row.studentName, 'matricule': student['matricule'] ?? row.matricule, 'classe': student['classLabel'] ?? row.classLabel ?? ''},
          'annee': {'libelle': '2026-2027'},
          'periode': {'libelle': live['periodLabel'] ?? 'Période'},
          'date': {'jour': '${now.day.toString().padLeft(2,'0')}/${now.month.toString().padLeft(2,'0')}/${now.year}'},
          'resultats': {
            'moyenne': live['average'] != null ? (live['average'] as num).toDouble().toStringAsFixed(2) : '-',
            'rang': live['rank']?.toString() ?? '',
            'mention': (live['mention'] ?? '').toString(),
            'appreciation': (live['appreciation'] ?? '').toString(),
            'details': lines,
          },
        };
        final bytes = await pdf.renderTemplate(templateContent: content, context: ctx, pageFormat: tpl.pageFormat);
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'bulletin_studio_${row.matricule}.pdf');
      } catch (e) { _snack('Erreur bulletin (modèle): $e'); }
      return;
    }

    await renderStandard(live);
  }

  Future<void> _quickEdit(GradeRow row) async {
    final auth = ref.read(authControllerProvider);
    final scoreCtrl = TextEditingController(text: row.score?.toString() ?? '');
    final obsCtrl = TextEditingController(text: row.observation ?? '');
    final compCtrl = TextEditingController(text: row.competencyCode ?? '');
    final status = ValueNotifier<String>(row.validationStatus);
    final mastery = ValueNotifier<String?>(row.masteryLevel);
    final exempt = ValueNotifier<bool>(row.isExempt);
    final cfg = ref.read(appConfigProvider).valueOrNull ?? AppConfig.defaults;
    final masteryLevels = <String?>[null, ...cfg.masteryLevels];
    final compCode = ValueNotifier<String?>((row.competencyCode ?? '').trim().isEmpty ? null : row.competencyCode!.trim());
    final cfgCodes = cfg.competencyCodes;
    final compOptions = <String?>{null, ...cfgCodes, if (compCode.value != null) compCode.value!}.toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Saisie/édition note - ${row.studentName}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${row.subjectName ?? row.label} • ${row.label}'),
            const SizedBox(height: 8),
            TextField(
                controller: scoreCtrl,
                decoration: InputDecoration(
                    labelText: 'Note / ${row.maxScore.toStringAsFixed(0)}'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),
            ValueListenableBuilder<bool>(valueListenable: exempt, builder: (c,v,_)=>CheckboxListTile(contentPadding: EdgeInsets.zero, value: v, onChanged: (nv)=>exempt.value=nv??false, title: const Text('Dispensé (neutralisé dans les moyennes)'))),
            ValueListenableBuilder<String?>(valueListenable: mastery, builder: (c,v,_)=>DropdownButtonFormField<String?>(
              initialValue: v,
              decoration: const InputDecoration(labelText: 'Niveau de maîtrise (compétences/socle)'),
              items: masteryLevels.map((m)=>DropdownMenuItem<String?>(value:m, child: Text(m ?? '— Non renseigné —'))).toList(),
              onChanged: (nv)=>mastery.value=nv,
            )),
            if (cfgCodes.isNotEmpty)
              ValueListenableBuilder<String?>(valueListenable: compCode, builder: (c,v,_)=>DropdownButtonFormField<String?>(
                initialValue: v,
                decoration: const InputDecoration(labelText: 'Compétence / code (optionnel)'),
                items: compOptions.map((m)=>DropdownMenuItem<String?>(value:m, child: Text(m ?? '— Non renseigné —'))).toList(),
                onChanged: (nv){ compCode.value=nv; compCtrl.text = nv ?? ''; },
              ))
            else
              TextField(controller: compCtrl, decoration: const InputDecoration(labelText: 'Compétence / code (optionnel)')),
            TextField(
                controller: obsCtrl,
                decoration: const InputDecoration(labelText: 'Observation')),
            const SizedBox(height: 8),
            ValueListenableBuilder<String>(
                valueListenable: status,
                builder: (c, v, _) => DropdownButtonFormField<String>(
                      initialValue: v,
                      decoration: const InputDecoration(labelText: 'Statut'),
                      items: const [
                        DropdownMenuItem(
                            value: 'Brouillon', child: Text('Brouillon')),
                        DropdownMenuItem(
                            value: 'Validée', child: Text('Validée')),
                      ],
                      onChanged: (nv) => status.value = nv ?? v,
                    )),
          ])),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(gradesRepositoryProvider).upsertGrade(
              id: row.id,
              studentId: row.studentId,
              classId: null,
              subjectId: row.subjectId,
              label: row.label,
              score: double.tryParse(scoreCtrl.text.replaceAll(',', '.')),
              maxScore: row.maxScore,
              coefficient: row.coefficient,
              isExempt: exempt.value,
              masteryLevel: mastery.value,
              competencyCode: cfgCodes.isNotEmpty ? compCode.value : (compCtrl.text.trim().isEmpty ? null : compCtrl.text.trim()),
              observation:
                  obsCtrl.text.trim().isEmpty ? null : obsCtrl.text.trim(),
              validationStatus: status.value,
              actorUserId: auth.userId,
              actorUsername: auth.username,
            );
        ref.invalidate(gradesListProvider);
        _snack('Note mise à jour.');
      } catch (e) {
        _snack('Erreur : $e');
      }
    }
  }

  Future<void> _newGrade() async {
    final auth = ref.read(authControllerProvider);
    final students = await ref.read(studentsRepositoryProvider).list(
          actorUserId: auth.userId,
          classId: _classId,
          limit: 500,
        );
    final subjects = await ref.read(timetableSubjectsProvider.future);
    final periods = await ref.read(periodsProvider.future);
    if (!mounted) return;
    if (students.isEmpty) {
      _snack('Aucun élève pour cette sélection.');
      return;
    }

    String? studentId = students.first.id;
    String? classId = _classId ?? students.first.classId;
    String? subjectId = subjects.isNotEmpty ? subjects.first.id : null;
    String? periodId = periods.isNotEmpty ? periods.first.id : null;
    final labelCtrl = TextEditingController(text: 'Devoir');
    final scoreCtrl = TextEditingController();
    final maxCtrl = TextEditingController(text: '20');
    final coefCtrl = TextEditingController(text: '1');
    final compCtrl = TextEditingController();
    var status = 'Brouillon';
    var isExempt = false;
    String? masteryLevel;
    String? competencyCode;
    final cfg = ref.read(appConfigProvider).valueOrNull ?? AppConfig.defaults;
    final masteryLevels = <String?>[null, ...cfg.masteryLevels];
    final cfgCodes = cfg.competencyCodes;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nouvelle évaluation'),
          content: SizedBox(
            width: 540,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: studentId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Élève'),
                items: students
                    .map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(
                              '${s.matricule} — ${s.fullName}${s.classLabel == null ? '' : ' (${s.classLabel})'}',
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setDialogState(() {
                    studentId = v;
                    classId = students.firstWhere((s) => s.id == v).classId;
                  });
                },
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: subjectId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Matière'),
                    items: subjects
                        .map((s) => DropdownMenuItem<String?>(
                            value: s.id, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => subjectId = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: periodId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Période'),
                    items: periods
                        .map((p) => DropdownMenuItem<String?>(
                            value: p.id, child: Text(p.name)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => periodId = v),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Libellé (ex: Devoir surveillé n°1)')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                      controller: scoreCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Note')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                      controller: maxCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Barème')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                      controller: coefCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Coefficient')),
                ),
              ]),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: isExempt,
                onChanged: (v) => setDialogState(() => isExempt = v ?? false),
                title: const Text('Dispensé (neutralisé dans les moyennes)'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              DropdownButtonFormField<String?>(
                initialValue: masteryLevel,
                decoration: const InputDecoration(labelText: 'Niveau de maîtrise (compétences/socle)'),
                items: masteryLevels.map((m)=>DropdownMenuItem<String?>(value:m, child: Text(m ?? '— Non renseigné —'))).toList(),
                onChanged: (v) => setDialogState(() => masteryLevel = v),
              ),
              if (cfgCodes.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: competencyCode,
                  decoration: const InputDecoration(labelText: 'Compétence / code (optionnel)'),
                  items: <String?>{null, ...cfgCodes, if (competencyCode != null) competencyCode}.map((m)=>DropdownMenuItem<String?>(value:m, child: Text(m ?? '— Non renseigné —'))).toList(),
                  onChanged: (v) => setDialogState(() { competencyCode = v; compCtrl.text = v ?? ''; }),
                )
              else
                TextField(controller: compCtrl, decoration: const InputDecoration(labelText: 'Compétence / code (optionnel)')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Statut'),
                items: const [
                  DropdownMenuItem(
                      value: 'Brouillon', child: Text('Brouillon')),
                  DropdownMenuItem(value: 'Validée', child: Text('Validée')),
                ],
                onChanged: (v) =>
                    setDialogState(() => status = v ?? 'Brouillon'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true || studentId == null) return;
    final label = labelCtrl.text.trim();
    if (label.isEmpty) {
      _snack('Le libellé est obligatoire.');
      return;
    }
    try {
      await ref.read(gradesRepositoryProvider).upsertGrade(
            studentId: studentId!,
            classId: classId,
            subjectId: subjectId,
            periodId: periodId,
            label: label,
            score: double.tryParse(scoreCtrl.text.replaceAll(',', '.')),
            maxScore: double.tryParse(maxCtrl.text.replaceAll(',', '.')) ?? 20,
            coefficient:
                double.tryParse(coefCtrl.text.replaceAll(',', '.')) ?? 1,
            isExempt: isExempt,
            masteryLevel: masteryLevel,
            competencyCode: cfgCodes.isNotEmpty ? competencyCode : (compCtrl.text.trim().isEmpty ? null : compCtrl.text.trim()),
            validationStatus: status,
            actorUserId: auth.userId,
            actorUsername: auth.username,
          );
      ref.invalidate(gradesListProvider);
      _snack('Évaluation enregistrée.');
    } catch (e) {
      _snack('Erreur : $e');
    }
  }

  Future<void> _validate(GradeRow row) async {
    final auth = ref.read(authControllerProvider);
    try {
      await ref.read(gradesRepositoryProvider).setValidation(
            gradeId: row.id,
            status: row.validationStatus == 'Validée' ? 'Brouillon' : 'Validée',
            actorUserId: auth.userId,
            actorUsername: auth.username,
          );
      ref.invalidate(gradesListProvider);
      _snack(row.validationStatus == 'Validée'
          ? 'Note repassée en brouillon.'
          : 'Note validée.');
    } catch (e) {
      _snack('Erreur validation : $e');
    }
  }

  Future<void> _downloadGradeTemplate() async {
    try {
      final choice = await showDialog<String>(context: context, builder: (ctx)=>SimpleDialog(title: const Text('Modèle d\'import notes'), children: [
        SimpleDialogOption(onPressed: ()=>Navigator.pop(ctx,'csv'), child: const ListTile(leading: Icon(Icons.description_outlined), title: Text('Télécharger modèle CSV (exemple inclus)'))),
        SimpleDialogOption(onPressed: ()=>Navigator.pop(ctx,'xlsx'), child: const ListTile(leading: Icon(Icons.grid_on_outlined), title: Text('Télécharger modèle Excel XLSX (exemple inclus)'))),
      ]));
      if (choice == null) return;
      final ts = DateTime.now().millisecondsSinceEpoch;
      File file;
      if (choice == 'xlsx') {
        file = await XlsxExport.export(filename: 'modele_import_notes_$ts.xlsx', sheetName: 'Notes', headers: GradesImportService.templateHeaders, rows: GradesImportService.templateSample);
      } else {
        file = await CsvExport.export(filename: 'modele_import_notes_$ts.csv', headers: GradesImportService.templateHeaders, rows: GradesImportService.templateSample);
      }
      if (mounted) _snack('Modèle enregistré : ${file.path}');
    } catch (e) {
      _snack('Erreur modèle : $e');
    }
  }

  Future<void> _importGrades() async {
    final pick = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'xlsx', 'xls']);
    if (pick == null || pick.files.single.path == null) return;
    final file = File(pick.files.single.path!);
    final auth = ref.read(authControllerProvider);
    try {
      final service = GradesImportService();
      final raw = await service.parseFile(file);
      final db = ref.read(appDatabaseProvider);
      final students = await ref.read(studentsRepositoryProvider).list(actorUserId: auth.userId, limit: 2000);
      final studentIdByMatricule = <String, String>{};
      final studentNameByMatricule = <String, String>{};
      final studentClassById = <String, String?>{};
      for (final s in students) {
        studentIdByMatricule[s.matricule] = s.id;
        studentNameByMatricule[s.matricule] = s.fullName;
        studentClassById[s.id] = s.classId;
      }
      final subjects = await ref.read(timetableSubjectsProvider.future);
      final subjectIdByLabel = <String, String>{};
      for (final s in subjects) {
        subjectIdByLabel[s.name.toLowerCase()] = s.id;
        subjectIdByLabel[s.code.toLowerCase()] = s.id;
      }
      final periods = await ref.read(periodsProvider.future);
      final periodIdByLabel = <String, String>{};
      for (final p in periods) {
        periodIdByLabel[p.name.toLowerCase()] = p.id;
      }

      final rows = service.toRows(
        raw,
        studentIdByMatricule: studentIdByMatricule,
        studentNameByMatricule: studentNameByMatricule,
        subjectIdByLabel: subjectIdByLabel,
        periodIdByLabel: periodIdByLabel,
      );
      if (!mounted) return;
      if (rows.isEmpty) {
        _snack('Aucune ligne valide trouvée dans le fichier.');
        return;
      }
      final selected = List<bool>.filled(rows.length, false);
      for (var i = 0; i < rows.length; i++) {
        selected[i] = rows[i].error == null && !rows[i].duplicate;
      }

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
          title: const Text('Import notes (prévisualisation & doublons)'),
          content: SizedBox(width: 1000, height: 540, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${rows.length} ligne(s) détectée(s). Les erreurs/doublons sont exclus par défaut. La matière et la période doivent correspondre aux libellés existants.', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Expanded(child: SingleChildScrollView(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
              columns: const [DataColumn(label: Text('Importer')), DataColumn(label: Text('Élève')), DataColumn(label: Text('Matière')), DataColumn(label: Text('Période')), DataColumn(label: Text('Libellé')), DataColumn(label: Text('Note/Maîtrise')), DataColumn(label: Text('État'))],
              rows: List.generate(rows.length, (i) {
                final r = rows[i];
                final ok = r.error == null && !r.duplicate;
                final val = r.isExempt ? 'Dispensé' : (r.masteryLevel != null && r.masteryLevel!.isNotEmpty ? (r.score != null ? '${r.score}/${r.maxScore} • ${r.masteryLevel}' : r.masteryLevel!) : (r.score?.toString() ?? '-'));
                return DataRow(cells: [
                  DataCell(Checkbox(value: selected[i], onChanged: ok ? (v)=>setD(()=>selected[i]=v??false) : null)),
                  DataCell(Text(r.studentName ?? r.studentMatricule)),
                  DataCell(Text(r.subjectLabel)),
                  DataCell(Text(r.periodLabel)),
                  DataCell(Text(r.evalLabel)),
                  DataCell(Text(val)),
                  DataCell(Text(r.error ?? (ok ? 'Prêt' : 'Ignoré'), style: TextStyle(fontSize: 11, color: ok ? const Color(0xFF059669) : const Color(0xFFDC2626)))),
                ]);
              }),
            )))),
          ])),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton.icon(onPressed: () async {
              var imported = 0; var failed = 0;
              for (var i = 0; i < rows.length; i++) {
                if (!selected[i]) continue;
                final r = rows[i];
                try {
                  await ref.read(gradesRepositoryProvider).upsertGrade(
                    studentId: r.studentId!,
                    classId: studentClassById[r.studentId!],
                    subjectId: r.subjectId,
                    periodId: r.periodId,
                    label: r.evalLabel,
                    score: r.score,
                    maxScore: r.maxScore,
                    coefficient: r.coefficient,
                    isExempt: r.isExempt,
                    masteryLevel: r.masteryLevel,
                    observation: r.observation,
                    validationStatus: 'Brouillon',
                    actorUserId: auth.userId,
                    actorUsername: auth.username,
                  );
                  imported++;
                } catch (_) { failed++; }
              }
              ref.invalidate(gradesListProvider);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) _snack('Import terminé: $imported importée(s), $failed échec(s).');
            }, icon: const Icon(Icons.playlist_add_check, size: 16), label: const Text('Importer la sélection')),
          ],
        )),
      );
    } catch (e) {
      _snack('Erreur import notes: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final classesAsync = ref.watch(classesProvider);
    final gradesAsync =
        ref.watch(gradesListProvider((classId: _classId, subjectId: null)));

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF020617)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Évaluations & Notes'),
        actions: [
                    OutlinedButton.icon(
            onPressed: _downloadGradeTemplate,
            icon: const Icon(Icons.download_outlined, size: 14),
            label: const Text('Modèle'),
          ),
          const SizedBox(width: 8),
OutlinedButton.icon(
            onPressed: _importGrades,
            icon: const Icon(Icons.upload_file_outlined, size: 16),
            label: const Text('Importer'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => context.go('/grades/councils'),
            icon: const Icon(Icons.groups_outlined, size: 16),
            label: const Text('Conseils & périodes'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _newGrade,
            icon: const Icon(Icons.add_chart_outlined, size: 16),
            label: const Text('Nouvelle note'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          gradesAsync.maybeWhen(
            data: (rows) {
              final avg = GradesRepository.weightedAverage(rows);
              final validated =
                  rows.where((r) => r.validationStatus == 'Validée').length;
              final drafts =
                  rows.where((r) => r.validationStatus != 'Validée').length;
              final exempt = rows.where((r) => r.isExempt).length;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                AppStatCard(
                  icon: Icons.grading_outlined,
                  label: 'Notes',
                  value: '${rows.length}',
                  hint: _classId == null
                      ? 'Toutes les classes'
                      : 'Classe sélectionnée',
                  tone: AppTone.info,
                ),
                AppStatCard(
                  icon: Icons.percent_outlined,
                  label: 'Moyenne pondérée',
                  value: avg == null ? '—' : '${avg.toStringAsFixed(2)} / 20',
                  tone: avg != null && avg >= 10
                      ? AppTone.success
                      : AppTone.warning,
                ),
                AppStatCard(
                  icon: Icons.verified_outlined,
                  label: 'Validées',
                  value: '$validated',
                  tone: AppTone.success,
                ),
                AppStatCard(
                  icon: Icons.edit_note_outlined,
                  label: 'Brouillons',
                  value: '$drafts',
                  tone: drafts > 0 ? AppTone.warning : AppTone.neutral,
                ),
                AppStatCard(
                  icon: Icons.block_outlined,
                  label: 'Dispensés',
                  value: '$exempt',
                  tone: AppTone.neutral,
                ),
              ]);
            },
            orElse: () => const SizedBox(height: 64),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  SizedBox(
                    width: 230,
                    child: classesAsync.when(
                      data: (classes) {
                        return DropdownButtonFormField<String?>(
                          initialValue: _classId,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Classe'),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('Toutes')),
                            ...classes.map((c) => DropdownMenuItem(
                                value: c.id, child: Text(c.label))),
                          ],
                          onChanged: (v) => setState(() {
                            _classId = v;
                            _subjectId = null;
                          }),
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Erreur : $e'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 210,
                    child: gradesAsync.maybeWhen(
                      data: (rows) {
                        final subjects = <String, String>{};
                        for (final row in rows) {
                          if (row.subjectId != null &&
                              row.subjectName != null) {
                            subjects[row.subjectId!] = row.subjectName!;
                          }
                        }
                        return DropdownButtonFormField<String?>(
                          initialValue: _subjectId,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Matière'),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('Toutes')),
                            ...subjects.entries.map((e) => DropdownMenuItem(
                                value: e.key, child: Text(e.value))),
                          ],
                          onChanged: (v) => setState(() => _subjectId = v),
                        );
                      },
                      orElse: () => const LinearProgressIndicator(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 240,
                    height: 38,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: 'Élève ou matricule...',
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _query = '');
                                },
                              ),
                      ),
                      onChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<String>(
                      initialValue: _statusFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Statut'),
                      items: const ['Tous', 'Brouillon', 'Validée']
                          .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _statusFilter = v ?? 'Tous'),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            gradesAsync.maybeWhen(
              data: (rows) =>
                  AppBadge('${rows.length} note(s)', tone: AppTone.neutral),
              orElse: () => const SizedBox.shrink(),
            ),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: gradesAsync.when(
              data: (rows) {
                final filtered = rows.where((r) {
                  if (_subjectId != null && r.subjectId != _subjectId)
                    return false;
                  if (_statusFilter != 'Tous' &&
                      r.validationStatus != _statusFilter) {
                    return false;
                  }
                  if (_query.isEmpty) return true;
                  return r.studentName.toLowerCase().contains(_query) ||
                      r.matricule.toLowerCase().contains(_query);
                }).toList();
                if (filtered.isEmpty) {
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: AppEmptyState(
                      icon: Icons.grading_outlined,
                      title: rows.isEmpty ? 'Aucune note' : 'Aucune note dans ce filtre',
                      message: rows.isEmpty
                          ? 'Importez les données de test (940 évaluations) ou saisissez une note.'
                          : null,
                      action: rows.isEmpty
                          ? FilledButton(onPressed: _newGrade, child: const Text('Nouvelle note'))
                          : null,
                    ),
                  );
                }
                final masteryCounts = <String, int>{};
                int exemptCount = 0;
                final compSet = <String>{};
                final compScores = <String, List<double>>{};
                for (final r in filtered) {
                  if (r.isExempt) exemptCount++;
                  final ml = (r.masteryLevel ?? '').trim();
                  if (ml.isNotEmpty) masteryCounts[ml] = (masteryCounts[ml] ?? 0) + 1;
                  final cc = (r.competencyCode ?? '').trim();
                  if (cc.isNotEmpty) {
                    compSet.add(cc);
                    if (!r.isExempt && r.score != null && r.maxScore > 0) {
                      compScores.putIfAbsent(cc, () => <double>[]).add((r.score! / r.maxScore) * 20.0);
                    }
                  }
                }
                final compAvg = compScores.entries.map((e) {
                  final avg = e.value.reduce((a,b)=>a+b) / e.value.length;
                  return MapEntry(e.key, avg);
                }).toList()..sort((a,b)=>a.key.compareTo(b.key));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppSectionCard(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      title: 'Synthèse compétences / maîtrise',
                      subtitle: '${filtered.length} note(s) • ${compSet.length} compétence(s) renseignée(s) • $exemptCount dispense(s)',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final e in masteryCounts.entries)
                            AppBadge('${e.key} : ${e.value}', tone: AppTone.info),
                          if (masteryCounts.isEmpty)
                            Text('Aucun niveau de maîtrise renseigné sur ce filtre.',
                                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ]),
                        if (compSet.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('Compétences : ${(compSet.toList()..sort()).join(', ')}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                        if (compAvg.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            for (final e in compAvg)
                              AppBadge('${e.key}: ${e.value.toStringAsFixed(1)}/20', tone: e.value >= 10 ? AppTone.success : AppTone.warning),
                          ]),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Élève')),
                                DataColumn(label: Text('Classe')),
                                DataColumn(label: Text('Matière')),
                                DataColumn(label: Text('Évaluation')),
                                DataColumn(label: Text('Note')),
                                DataColumn(label: Text('Barème')),
                                DataColumn(label: Text('Coef')),
                                DataColumn(label: Text('Statut')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: filtered.map((r) {
                                final ratio = r.maxScore == 0 || r.score == null
                                    ? null
                                    : r.score! / r.maxScore * 20;
                                return DataRow(cells: [
                                  DataCell(Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(r.studentName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      Text(r.matricule,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              fontFamily: 'monospace')),
                                    ],
                                  )),
                                  DataCell(Text(r.classLabel ?? '-')),
                                  DataCell(Text(
                                      r.subjectName ?? r.subjectId ?? '-')),
                                  DataCell(Text(r.label)),
                                  DataCell(r.isExempt
                                      ? const AppBadge('Dispensé',
                                          tone: AppTone.warning,
                                          icon: Icons.block_outlined)
                                      : Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            AppBadge(
                                              r.score == null
                                                  ? '—'
                                                  : '${r.score!.toStringAsFixed(2)}/${r.maxScore.toStringAsFixed(0)}',
                                              tone: ratio == null
                                                  ? AppTone.neutral
                                                  : (ratio >= 10
                                                      ? AppTone.success
                                                      : AppTone.danger),
                                            ),
                                            if (r.masteryLevel != null && r.masteryLevel!.isNotEmpty)
                                              Text(r.masteryLevel!, style: const TextStyle(fontSize: 10, color: Color(0xFF2563EB))),
                                          ],
                                        )),
                                  DataCell(Text(r.maxScore.toStringAsFixed(0))),
                                  DataCell(
                                      Text(r.coefficient.toStringAsFixed(2))),
                                  DataCell(AppBadge(
                                    r.validationStatus,
                                    tone: r.validationStatus == 'Validée'
                                        ? AppTone.success
                                        : AppTone.warning,
                                    icon: r.validationStatus == 'Validée'
                                        ? Icons.verified_outlined
                                        : Icons.edit_note_outlined,
                                  )),
                                  DataCell(Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Modifier',
                                          icon: const Icon(Icons.edit_outlined,
                                              size: 18),
                                          onPressed: () => _quickEdit(r),
                                        ),
                                        IconButton(
                                          tooltip:
                                              r.validationStatus == 'Validée'
                                                  ? 'Repasser en brouillon'
                                                  : 'Valider la note',
                                          icon: Icon(
                                            r.validationStatus == 'Validée'
                                                ? Icons.undo_outlined
                                                : Icons.check_circle_outline,
                                            size: 18,
                                          ),
                                          onPressed: () => _validate(r),
                                        ),
                                        IconButton(
                                          tooltip: 'Bulletin PDF',
                                          icon: const Icon(
                                              Icons.picture_as_pdf_outlined,
                                              size: 18),
                                          onPressed: () => _generateBulletin(r),
                                        ),
                                      ])),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text(
                      'Erreur chargement notes : $e\n(Vérifiez la permission grades.read)')),
            ),
          ),
        ]),
      ),
    );
  }
}
