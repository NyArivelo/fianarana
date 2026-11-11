import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/database/app_database.dart';
import '../academics/academics_providers.dart';
import '../auth/auth_controller.dart';
import '../documents/document_service.dart';
import '../settings/settings_providers.dart';
import 'grades_providers.dart';
import 'grades_repository.dart';

class GradesScreen extends ConsumerStatefulWidget {
  const GradesScreen({super.key});
  @override
  ConsumerState<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends ConsumerState<GradesScreen> {
  String? _classId;
  String? _periodId;
  String? _selectedEvalId;

  @override
  Widget build(BuildContext context) {
    final years = ref.watch(academicYearsProvider).valueOrNull ?? [];
    final year = years.where((y) => y.isCurrent).firstOrNull ?? (years.isNotEmpty ? years.first : null);
    final classes = ref.watch(classesProvider(year?.id)).valueOrNull ?? [];
    final periods = year == null ? <Period>[] : (ref.watch(periodsProvider(year.id)).valueOrNull ?? []);
    final subjects = {for (final s in (ref.watch(subjectsProvider).valueOrNull ?? <Subject>[])) s.id: s};
    _classId ??= classes.isNotEmpty ? classes.first.id : null;

    final evals = ref.watch(evaluationsProvider((classId: _classId, periodId: _periodId))).valueOrNull ?? [];
    final selected = evals.firstWhereOrNull((e) => e.id == _selectedEvalId);

    final selectedPeriod = periods.firstWhereOrNull((p) => p.id == _periodId);
    final user = ref.watch(authControllerProvider).currentUser;

    return DefaultTabController(length: 3, child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: Row(children: [
        if (selectedPeriod != null) Chip(label: Text(selectedPeriod.isClosed ? 'Période clôturée (verrouillée)' : 'Période ouverte'), avatar: Icon(selectedPeriod.isClosed ? Icons.lock : Icons.lock_open, size: 16)),
        const Spacer(),
        if (selectedPeriod != null)
          FilledButton.tonalIcon(
            onPressed: () async {
              try {
                if (selectedPeriod.isClosed) {
                  await ref.read(gradesRepositoryProvider).unlockPeriod(selectedPeriod.id, userId: user?.id, username: user?.displayName, reason: 'Déverrouillage manuel (direction)');
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Période déverrouillée (action auditée).')));
                } else {
                  await ref.read(gradesRepositoryProvider).lockPeriod(selectedPeriod.id, userId: user?.id, username: user?.displayName);
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Période clôturée/verrouillée.')));
                }
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
              }
            },
            icon: Icon(selectedPeriod.isClosed ? Icons.lock_open : Icons.lock),
            label: Text(selectedPeriod.isClosed ? 'Déverrouiller la période' : 'Clôturer/verrouiller la période'),
          ),
      ])),
      const TabBar(tabs: [Tab(text: 'Évaluations & Saisie des notes'), Tab(text: 'Conseil de classe'), Tab(text: 'Bulletins (base)')]),
      Expanded(child: TabBarView(children: [
        Row(children: [
          SizedBox(width: 420, child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownButtonFormField<String>(initialValue: _classId, decoration: const InputDecoration(labelText: 'Classe'), items: [for (final c in classes) DropdownMenuItem(value: c.id, child: Text(c.name))], onChanged: (v)=>setState((){_classId=v; _selectedEvalId=null;})),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(initialValue: _periodId, decoration: const InputDecoration(labelText: 'Période (filtre)'), items: [const DropdownMenuItem(value: null, child: Text('Toutes')), for (final p in periods) DropdownMenuItem(value: p.id, child: Text(p.name))], onChanged: (v)=>setState((){_periodId=v; _selectedEvalId=null;})),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: _classId==null?null:()=>_newEval(context, ref, year, periods), icon: const Icon(Icons.add), label: const Text('Nouvelle évaluation')),
            const SizedBox(height: 12),
            Expanded(child: evals.isEmpty ? const Text('Aucune évaluation.') : ListView.builder(itemCount: evals.length, itemBuilder: (context,i){ final e=evals[i]; return ListTile(selected: e.id==_selectedEvalId, title: Text(e.title), subtitle: Text('${subjects[e.subjectId]?.name ?? ''} • coef ${e.coefficient} / ${e.maxScore}'), onTap: ()=>setState(()=>_selectedEvalId=e.id)); })),
          ]))),
          const VerticalDivider(width: 1),
          Expanded(child: selected == null || _classId == null ? const Center(child: Text('Sélectionnez une évaluation pour saisir les notes.')) : _GradeEntry(evaluation: selected, classId: _classId!, academicYearId: year?.id)),
        ]),
        _CouncilTab(classId: _classId, periodId: _periodId, academicYearId: year?.id),
        _BulletinTab(classId: _classId, periodId: _periodId, academicYearId: year?.id),
      ])),
    ]));
  }

  Future<void> _newEval(BuildContext context, WidgetRef ref, AcademicYear? year, List<Period> periods) async {
    if (_classId == null) return;
    final subjects = ref.read(subjectsProvider).valueOrNull ?? [];
    if (subjects.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Créez d\'abord des matières.'))); return; }
    String subjectId = subjects.first.id;
    String? periodId = _periodId;
    final title = TextEditingController();
    final coef = TextEditingController(text: '1');
    final max = TextEditingController(text: '20');
    await showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setState)=>AlertDialog(
      title: const Text('Nouvelle évaluation'),
      content: SizedBox(width:420, child: Column(mainAxisSize:MainAxisSize.min, children:[
        DropdownButtonFormField<String>(initialValue: subjectId, decoration: const InputDecoration(labelText:'Matière'), items:[for(final s in subjects) DropdownMenuItem(value:s.id, child:Text(s.name))], onChanged:(v)=>setState(()=>subjectId=v??subjectId)),
        const SizedBox(height:8),
        DropdownButtonFormField<String?>(initialValue: periodId, decoration: const InputDecoration(labelText:'Période'), items:[const DropdownMenuItem(value:null, child:Text('(Aucune)')), for(final p in periods) DropdownMenuItem(value:p.id, child:Text(p.name))], onChanged:(v)=>setState(()=>periodId=v)),
        const SizedBox(height:8),
        TextField(controller:title, decoration: const InputDecoration(labelText:'Titre (ex: Devoir 1)')),
        Row(children:[Expanded(child: TextField(controller:coef, decoration: const InputDecoration(labelText:'Coefficient'), keyboardType: TextInputType.number)), const SizedBox(width:8), Expanded(child: TextField(controller:max, decoration: const InputDecoration(labelText:'Barème (max)'), keyboardType: TextInputType.number))]),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed:() async { if(title.text.trim().isEmpty) return; await ref.read(gradesRepositoryProvider).upsertEvaluation(academicYearId: year?.id, periodId: periodId, classId: _classId!, subjectId: subjectId, title: title.text.trim(), coefficient: double.tryParse(coef.text.replaceAll(',', '.')) ?? 1, maxScore: double.tryParse(max.text.replaceAll(',', '.')) ?? 20); if(ctx.mounted) Navigator.pop(ctx); }, child: const Text('Créer'))],
    )));
  }
}

class _GradeEntry extends ConsumerStatefulWidget {
  final Evaluation evaluation;
  final String classId;
  final String? academicYearId;
  const _GradeEntry({required this.evaluation, required this.classId, this.academicYearId});
  @override
  ConsumerState<_GradeEntry> createState() => _GradeEntryState();
}

class _GradeEntryState extends ConsumerState<_GradeEntry> {
  late Future<List<Student>> _students;
  @override
  void initState(){ super.initState(); _students = ref.read(gradesRepositoryProvider).studentsForClass(widget.classId, academicYearId: widget.academicYearId); }
  @override
  void didUpdateWidget(covariant _GradeEntry oldWidget){ super.didUpdateWidget(oldWidget); if (oldWidget.classId!=widget.classId || oldWidget.evaluation.id!=widget.evaluation.id) _students = ref.read(gradesRepositoryProvider).studentsForClass(widget.classId, academicYearId: widget.academicYearId); }

  @override
  Widget build(BuildContext context) {
    final grades = ref.watch(gradesForEvaluationProvider(widget.evaluation.id)).valueOrNull ?? [];
    final byStudent = {for (final g in grades) g.studentId: g};
    return FutureBuilder<List<Student>>(future: _students, builder: (context, snap){
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final students = snap.data!;
      if (students.isEmpty) return const Center(child: Text('Aucun élève inscrit dans cette classe.'));
      return ListView(children:[
        Padding(padding: const EdgeInsets.all(12), child: Text('Saisie: ${widget.evaluation.title} (/${widget.evaluation.maxScore})', style: Theme.of(context).textTheme.titleMedium)),
        DataTable(columns: const [DataColumn(label: Text('Élève')), DataColumn(label: Text('Note')), DataColumn(label: Text('Absent')), DataColumn(label: Text('Dispensé'))], rows: [
          for (final s in students)
            DataRow(cells: [
              DataCell(Text('${s.lastName} ${s.firstName}')),
              DataCell(SizedBox(width: 90, child: TextFormField(
                key: ValueKey('${widget.evaluation.id}-${s.id}-${byStudent[s.id]?.score}-${byStudent[s.id]?.updatedAt}'),
                initialValue: byStudent[s.id]?.score?.toString() ?? '',
                keyboardType: TextInputType.number,
                onFieldSubmitted: (v) async {
                  final val = double.tryParse(v.replaceAll(',', '.'));
                  final g = byStudent[s.id];
                  try {
                    await ref.read(gradesRepositoryProvider).setGrade(evaluationId: widget.evaluation.id, studentId: s.id, score: val, isAbsent: g?.isAbsent ?? false, isExempt: g?.isExempt ?? false);
                  } on PeriodLockedException catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                  }
                },
                decoration: const InputDecoration(isDense: true),
              ))),
              DataCell(Checkbox(value: byStudent[s.id]?.isAbsent ?? false, onChanged: (v) async { final g = byStudent[s.id]; try { await ref.read(gradesRepositoryProvider).setGrade(evaluationId: widget.evaluation.id, studentId: s.id, score: g?.score, isAbsent: v ?? false, isExempt: g?.isExempt ?? false); } on PeriodLockedException catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message))); } })),
              DataCell(Checkbox(value: byStudent[s.id]?.isExempt ?? false, onChanged: (v) async { final g = byStudent[s.id]; try { await ref.read(gradesRepositoryProvider).setGrade(evaluationId: widget.evaluation.id, studentId: s.id, score: g?.score, isAbsent: g?.isAbsent ?? false, isExempt: v ?? false); } on PeriodLockedException catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message))); } })),
            ]),
        ]),
        const Padding(padding: EdgeInsets.all(12), child: Text('Astuce: saisissez la note puis appuyez Entrée pour enregistrer. "Dispensé" neutralise la matière pour l\'élève.')),
      ]);
    });
  }
}

class _CouncilTab extends ConsumerStatefulWidget {
  final String? classId; final String? periodId; final String? academicYearId;
  const _CouncilTab({this.classId, this.periodId, this.academicYearId});
  @override
  ConsumerState<_CouncilTab> createState() => _CouncilTabState();
}

class _CouncilTabState extends ConsumerState<_CouncilTab> {
  @override
  Widget build(BuildContext context) {
    if (widget.classId == null || widget.periodId == null) {
      return const Center(child: Text('Sélectionnez une classe et une période pour accéder au conseil de classe.'));
    }
    final studentsF = ref.watch(gradesRepositoryProvider).studentsForClass(widget.classId!, academicYearId: widget.academicYearId);
    final decisions = ref.watch(councilDecisionsProvider((periodId: widget.periodId!, classId: widget.classId!))).valueOrNull ?? [];
    final byStudent = {for (final d in decisions) d.studentId: d};
    return FutureBuilder<List<Student>>(future: studentsF, builder: (context, snap){
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final students = snap.data!;
      if (students.isEmpty) return const Center(child: Text('Aucun élève inscrit dans cette classe.'));
      return ListView(padding: const EdgeInsets.all(16), children: [
        Text('Conseil de classe / Délibérations', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Saisissez l\'appréciation globale et la décision d\'orientation par élève pour la période sélectionnée.'),
        const SizedBox(height: 12),
        for (final s in students)
          Card(child: ListTile(
            title: Text('${s.lastName} ${s.firstName}'),
            subtitle: Text('Appréciation: ${byStudent[s.id]?.appreciation ?? '-'}\nDécision: ${byStudent[s.id]?.decision ?? '-'}'),
            isThreeLine: true,
            trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editDecision(context, s, byStudent[s.id])),
          )),
      ]);
    });
  }

  Future<void> _editDecision(BuildContext context, Student s, CouncilDecision? d) async {
    final app = TextEditingController(text: d?.appreciation ?? '');
    String? decision = d?.decision;
    final decisions = <String?>[null, 'passage', 'redoublement', 'avertissement_travail', 'avertissement_conduite', 'felicitations', 'encouragements', 'tableau_honneur'];
    await showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setState)=>AlertDialog(
      title: Text('Délibération - ${s.lastName} ${s.firstName}'),
      content: SizedBox(width:480, child: Column(mainAxisSize:MainAxisSize.min, children:[
        TextField(controller: app, decoration: const InputDecoration(labelText: 'Appréciation globale du conseil'), maxLines: 3),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(initialValue: decision, decoration: const InputDecoration(labelText: 'Décision / orientation'), items: [for (final x in decisions) DropdownMenuItem(value: x, child: Text(x ?? '(Aucune)'))], onChanged: (v)=>setState(()=>decision=v)),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed:() async {
        try {
          await ref.read(gradesRepositoryProvider).setCouncilDecision(periodId: widget.periodId!, classId: widget.classId!, studentId: s.id, appreciation: app.text.trim().isEmpty?null:app.text.trim(), decision: decision);
          if (ctx.mounted) Navigator.pop(ctx);
        } on PeriodLockedException catch (e) {
          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }, child: const Text('Enregistrer'))],
    )));
  }
}

class _BulletinTab extends ConsumerStatefulWidget {
  final String? classId; final String? periodId; final String? academicYearId;
  const _BulletinTab({this.classId, this.periodId, this.academicYearId});
  @override
  ConsumerState<_BulletinTab> createState() => _BulletinTabState();
}

class _BulletinTabState extends ConsumerState<_BulletinTab> {
  String? _studentId;
  @override
  Widget build(BuildContext context) {
    if (widget.classId == null) return const Center(child: Text('Sélectionnez une classe dans l\'onglet Notes.'));
    final studentsF = ref.watch(gradesRepositoryProvider).studentsForClass(widget.classId!, academicYearId: widget.academicYearId);
    final school = ref.watch(schoolSettingProvider).valueOrNull;
    final periods = widget.academicYearId == null ? <Period>[] : (ref.watch(periodsProvider(widget.academicYearId!)).valueOrNull ?? []);
    final periodLabel = periods.firstWhereOrNull((p)=>p.id==widget.periodId)?.name ?? 'Période';
    final decisions = (widget.periodId == null) ? <CouncilDecision>[] : (ref.watch(councilDecisionsProvider((periodId: widget.periodId!, classId: widget.classId!))).valueOrNull ?? []);
    return FutureBuilder<List<Student>>(future: studentsF, builder: (context, snap){
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final students = snap.data!;
      final selected = students.firstWhereOrNull((s)=>s.id==_studentId);
      final dec = decisions.firstWhereOrNull((d)=>d.studentId==selected?.id);
      return Row(children:[
        SizedBox(width:320, child: ListView(children:[ for(final s in students) ListTile(selected:s.id==_studentId, title: Text('${s.lastName} ${s.firstName}'), onTap: ()=>setState(()=>_studentId=s.id))])),
        const VerticalDivider(width:1),
        Expanded(child: selected==null ? const Center(child: Text('Sélectionnez un élève pour générer un bulletin.')) : FutureBuilder<Map<String, dynamic>>(
          future: () async {
            final repo = ref.read(gradesRepositoryProvider);
            final lines = await repo.bulletinLines(studentId: selected.id, classId: widget.classId!, periodId: widget.periodId, academicYearId: widget.academicYearId);
            // compute ranking
            final avgs = <String, double>{};
            for (final st in students) {
              final ls = await repo.bulletinLines(studentId: st.id, classId: widget.classId!, periodId: widget.periodId, academicYearId: widget.academicYearId);
              double total = 0, coefSum = 0;
              for (final l in ls) { final a = (l['average'] as num).toDouble(); final c = (l['coef'] as num).toDouble(); total += a*c; coefSum += c; }
              if (coefSum > 0) avgs[st.id] = total/coefSum;
            }
            final sorted = avgs.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
            final rank = sorted.indexWhere((e)=>e.key==selected.id);
            return {'lines': lines, 'rank': rank>=0 ? rank+1 : null, 'total': sorted.length};
          }(),
          builder: (context, bsnap){
            if (!bsnap.hasData) return const Center(child: CircularProgressIndicator());
            final data = bsnap.data!;
            final lines = (data['lines'] as List).cast<Map<String,dynamic>>();
            return PdfPreview(build: (format) => DocumentService().buildBulletin(
              student: selected, school: school, lines: lines, periodLabel: periodLabel,
              appreciation: dec?.appreciation, decision: dec?.decision,
              rank: data['rank'] as int?, totalStudents: data['total'] as int?,
            ));
          },
        )),
      ]);
    });
  }
}
