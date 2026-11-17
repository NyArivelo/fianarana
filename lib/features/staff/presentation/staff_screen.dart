import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/staff/data/staff_repository.dart';

final _staffRepoProvider = Provider((ref) => StaffRepository(ref.watch(appDatabaseProvider)));
final _staffListProvider = FutureProvider.family((ref, String? q) {
  final uid = ref.watch(authControllerProvider).userId;
  return ref.watch(_staffRepoProvider).list(actorUserId: uid, query: q);
});

enum _StaffFilter { tous, enseignantes, administration }

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});
  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  String? _q;
  _StaffFilter _filter = _StaffFilter.tous;

  Future<void> _addOrEdit([dynamic s]) async {
    final auth = ref.read(authControllerProvider);
    final num = TextEditingController(text: s?.staffNumber ?? '');
    final ln = TextEditingController(text: s?.lastName ?? '');
    final fn = TextEditingController(text: s?.firstName ?? '');
    final fct = TextEditingController(text: s?.functionTitle ?? '');
    final dep = TextEditingController(text: s?.departmentOrSubject ?? '');
    final phone = TextEditingController(text: s?.phone ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s == null ? 'Nouveau personnel' : 'Modifier personnel'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: num, decoration: const InputDecoration(labelText: 'Matricule RH')),
              const SizedBox(height: 8),
              TextField(controller: ln, decoration: const InputDecoration(labelText: 'Nom')),
              const SizedBox(height: 8),
              TextField(controller: fn, decoration: const InputDecoration(labelText: 'Prénom')),
              const SizedBox(height: 8),
              TextField(controller: fct, decoration: const InputDecoration(labelText: 'Fonction')),
              const SizedBox(height: 8),
              TextField(controller: dep, decoration: const InputDecoration(labelText: 'Matière/Service')),
              const SizedBox(height: 8),
              TextField(controller: phone, decoration: const InputDecoration(labelText: 'Téléphone')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(_staffRepoProvider).upsert(
              id: s?.id,
              staffNumber: num.text.trim(),
              lastName: ln.text.trim(),
              firstName: fn.text.trim(),
              functionTitle: fct.text.trim(),
              department: dep.text.trim(),
              phone: phone.text.trim(),
              actorUserId: auth.userId,
              actorUsername: auth.username,
            );
        ref.invalidate(_staffListProvider);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  bool _isTeacher(dynamic s) => (s.functionTitle ?? '').toString().toLowerCase().contains('enseign');

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_staffListProvider(_q));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Personnel & enseignants'),
        actions: [
          FilledButton.icon(
            onPressed: () => _addOrEdit(),
            icon: const Icon(Icons.person_add_alt_1, size: 16),
            label: const Text('Nouveau'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Row(children: [
              SizedBox(
                width: 300,
                height: 38,
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: 'Nom, matricule, fonction...'),
                  onChanged: (v) => setState(() => _q = v.trim().isEmpty ? null : v.trim()),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<_StaffFilter>(
                segments: const [
                  ButtonSegment(value: _StaffFilter.tous, label: Text('Tous')),
                  ButtonSegment(value: _StaffFilter.enseignantes, label: Text('Enseignantes')),
                  ButtonSegment(value: _StaffFilter.administration, label: Text('Administration')),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
              const Spacer(),
              list.maybeWhen(
                data: (rows) => Text('${rows.length} membre(s)', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                orElse: () => const SizedBox.shrink(),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: list.when(
              data: (rows) {
                final filtered = rows.where((s) {
                  if (_filter == _StaffFilter.enseignantes) return _isTeacher(s);
                  if (_filter == _StaffFilter.administration) return !_isTeacher(s);
                  return true;
                }).toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('Aucun membre du personnel trouvé.'));
                }
                return SingleChildScrollView(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: filtered.map((s) => _staffCard(context, s, isDark, border)).toList(),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erreur: $e')),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _staffCard(BuildContext context, dynamic s, bool isDark, Color border) {
    final initials = '${(s.lastName as String).isNotEmpty ? s.lastName[0] : ''}${(s.firstName as String).isNotEmpty ? s.firstName[0] : ''}';
    final teacher = _isTeacher(s);
    final accent = teacher ? const Color(0xFF2563EB) : const Color(0xFF7C3AED);
    return SizedBox(
      width: 300,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: accent.withValues(alpha: 0.12),
              child: Text(initials, style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s.lastName} ${s.firstName}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                Text(s.staffNumber, style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF64748B))),
              ]),
            ),
            _statusDot(s.status),
          ]),
          const SizedBox(height: 10),
          Text(s.functionTitle ?? '-', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (s.departmentOrSubject != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6)),
              child: Text(s.departmentOrSubject!, style: TextStyle(fontSize: 10, color: accent, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 6),
          if (s.phone != null)
            Row(children: [
              const Icon(Icons.phone_outlined, size: 12, color: Color(0xFF94A3B8)),
              const SizedBox(width: 4),
              Text(s.phone!, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
            ]),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Row(children: [
            if (teacher)
              TextButton.icon(
                onPressed: () => context.go('/timetable?teacher=${s.id}'),
                icon: const Icon(Icons.calendar_month_outlined, size: 15),
                label: const Text('Planning', style: TextStyle(fontSize: 11)),
              ),
            const Spacer(),
            IconButton(
              tooltip: 'Modifier',
              onPressed: () => _addOrEdit(s),
              icon: const Icon(Icons.edit_outlined, size: 17),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _statusDot(String status) {
    final active = status.toLowerCase() == 'actif';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: active ? const Color(0xFF047857) : const Color(0xFFB91C1C))),
    );
  }
}
