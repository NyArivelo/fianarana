import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:collection/collection.dart';

import '../../core/database/app_database.dart';
import '../academics/academics_providers.dart';
import '../settings/settings_providers.dart';
import '../auth/auth_controller.dart';
import 'admin_providers.dart';

class AdminSecurityTab extends ConsumerStatefulWidget {
  const AdminSecurityTab({super.key});
  @override
  ConsumerState<AdminSecurityTab> createState() => _AdminSecurityTabState();
}

class _AdminSecurityTabState extends ConsumerState<AdminSecurityTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(adminRepositoryProvider).ensureDefaultRoles());
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(length: 3, child: Column(children: const [
      TabBar(isScrollable: true, tabs: [Tab(text: 'Utilisateurs'), Tab(text: 'Rôles & Portées'), Tab(text: 'Journal d\'audit')]),
      Expanded(child: TabBarView(children: [_UsersTab(), _RolesTab(), _AuditTab()])),
    ]));
  }
}

class _UsersTab extends ConsumerWidget {
  const _UsersTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(adminUsersProvider);
    final roles = ref.watch(adminRolesProvider).valueOrNull ?? [];
    final roleNames = {for (final r in roles) r.id: r.name};
    return Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      Row(children: [Text('Gestion des utilisateurs', style: Theme.of(context).textTheme.titleMedium), const Spacer(), FilledButton.icon(onPressed: ()=>_editUser(context, ref, roles), icon: const Icon(Icons.add), label: const Text('Nouvel utilisateur'))]),
      const SizedBox(height: 12),
      Expanded(child: users.when(loading: ()=>const Center(child:CircularProgressIndicator()), error:(e,_)=>Center(child:Text('Erreur: $e')), data: (list)=> ListView.builder(itemCount: list.length, itemBuilder: (context,i){
        final u = list[i];
        return FutureBuilder<List<String>>(future: ref.read(adminRepositoryProvider).roleIdsForUser(u.id), builder: (context, snap){
          final rids = snap.data ?? [];
          final rnames = rids.map((id)=>roleNames[id] ?? id.substring(0,8)).join(', ');
          return ListTile(
            leading: Icon(u.isActive ? Icons.person : Icons.person_off),
            title: Text('${u.displayName} (${u.username})'),
            subtitle: Text('Rôles: ${rnames.isEmpty ? '-' : rnames} • ${u.isActive ? 'Actif' : 'Désactivé'}'),
            trailing: Wrap(spacing: 4, children: [
              IconButton(icon: const Icon(Icons.assignment_ind_outlined), tooltip: 'Affectations (portée restreinte)', onPressed: ()=>_assignments(context, ref, u)),
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: ()=>_editUser(context, ref, roles, u)),
              IconButton(icon: const Icon(Icons.lock_reset), tooltip: 'Réinitialiser mot de passe', onPressed: ()=>_resetPwd(context, ref, u)),
              IconButton(icon: Icon(u.isActive ? Icons.block : Icons.check_circle_outline), tooltip: u.isActive?'Désactiver':'Activer', onPressed: ()=>ref.read(adminRepositoryProvider).updateUser(u, isActive: !u.isActive)),
            ]),
          );
        });
      }))),
    ]));
  }

  static Future<void> _editUser(BuildContext context, WidgetRef ref, List<Role> roles, [User? u]) async {
    final display = TextEditingController(text: u?.displayName ?? '');
    final username = TextEditingController(text: u?.username ?? '');
    final email = TextEditingController(text: u?.email ?? '');
    final password = TextEditingController();
    List<String> selectedRoles = u == null ? [] : await ref.read(adminRepositoryProvider).roleIdsForUser(u.id);
    if (!context.mounted) return;
    await showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setState)=>AlertDialog(
      title: Text(u==null?'Nouvel utilisateur':'Modifier utilisateur'),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize:MainAxisSize.min, children:[
        TextField(controller: display, decoration: const InputDecoration(labelText:'Nom affiché')),
        if (u==null) TextField(controller: username, decoration: const InputDecoration(labelText:'Identifiant')),
        TextField(controller: email, decoration: const InputDecoration(labelText:'Email')),
        if (u==null) TextField(controller: password, decoration: const InputDecoration(labelText:'Mot de passe (min 8)'), obscureText: true),
        const SizedBox(height: 8),
        const Align(alignment: Alignment.centerLeft, child: Text('Rôles', style: TextStyle(fontWeight: FontWeight.bold))),
        for (final r in roles) CheckboxListTile(value: selectedRoles.contains(r.id), title: Text('${r.name} (${r.scope})'), onChanged: (v){ setState(()=> v==true ? selectedRoles.add(r.id) : selectedRoles.remove(r.id)); }, dense: true, controlAffinity: ListTileControlAffinity.leading),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed:() async {
        if (display.text.trim().isEmpty) return;
        if (u==null) {
          if (username.text.trim().isEmpty || password.text.length < 8) return;
          await ref.read(adminRepositoryProvider).createUser(username: username.text.trim(), displayName: display.text.trim(), password: password.text, email: email.text.trim().isEmpty?null:email.text.trim(), roleIds: selectedRoles);
        } else {
          await ref.read(adminRepositoryProvider).updateUser(u, displayName: display.text.trim(), email: email.text.trim(), roleIds: selectedRoles);
        }
        if (ctx.mounted) Navigator.pop(ctx);
      }, child: const Text('Enregistrer'))],
    )));
  }

  static Future<void> _resetPwd(BuildContext context, WidgetRef ref, User u) async {
    final p = TextEditingController();
    final pin = TextEditingController();
    await showDialog(context: context, builder: (ctx)=>AlertDialog(
      title: Text('Identifiants / PIN - ${u.username}'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: p, decoration: const InputDecoration(labelText:'Nouveau mot de passe (min 8, laisser vide pour ne pas changer)'), obscureText: true),
        const SizedBox(height: 8),
        TextField(controller: pin, decoration: const InputDecoration(labelText:'Code PIN (4-6 chiffres, vide pour effacer)'), keyboardType: TextInputType.number, obscureText: true),
        const SizedBox(height: 8),
        const Text('Le PIN permet le déverrouillage rapide et le changement d’utilisateur (Ctrl+L / Quick Switch).'),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed:() async {
        if (p.text.isNotEmpty) {
          if (p.text.length < 8) return;
          await ref.read(adminRepositoryProvider).resetPassword(u.id, p.text);
        }
        final pinVal = pin.text.trim();
        if (pinVal.isEmpty || (RegExp(r'^\d{4,6}$').hasMatch(pinVal))) {
          await ref.read(authServiceProvider).setPin(u.id, pinVal.isEmpty ? null : pinVal);
        }
        if(ctx.mounted) Navigator.pop(ctx);
      }, child: const Text('Enregistrer'))],
    ));
  }

  static Future<void> _assignments(BuildContext context, WidgetRef ref, User u) async {
    await showDialog(context: context, builder: (ctx) => _AssignmentsDialog(user: u));
  }
}

class _RolesTab extends ConsumerWidget {
  const _RolesTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(adminRolesProvider);
    return Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      Row(children: [Text('Rôles et portées', style: Theme.of(context).textTheme.titleMedium), const Spacer(), FilledButton.icon(onPressed: ()=>_editRole(context, ref), icon: const Icon(Icons.add), label: const Text('Nouveau rôle'))]),
      const SizedBox(height: 8),
      const Text('Portées: global (accès établissement), restricted (affectations), caisse (propres encaissements/journal).'),
      const SizedBox(height: 12),
      Expanded(child: roles.when(loading: ()=>const Center(child:CircularProgressIndicator()), error:(e,_)=>Center(child:Text('Erreur: $e')), data: (list)=> ListView.builder(itemCount: list.length, itemBuilder: (context,i){ final r=list[i]; return ListTile(title: Text(r.name), subtitle: Text('Portée: ${r.scope} • ${r.description ?? ''}${r.isSystem ? ' • système':''}'), trailing: r.isSystem && r.name=='Administrateur' ? null : IconButton(icon: const Icon(Icons.edit_outlined), onPressed: ()=>_editRole(context, ref, r))); }))),
    ]));
  }

  static Future<void> _editRole(BuildContext context, WidgetRef ref, [Role? r]) async {
    final name = TextEditingController(text: r?.name ?? '');
    final desc = TextEditingController(text: r?.description ?? '');
    String scope = r?.scope ?? 'global';
    await showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setState)=>AlertDialog(
      title: Text(r==null?'Nouveau rôle':'Modifier rôle'),
      content: SizedBox(width:420, child: Column(mainAxisSize:MainAxisSize.min, children:[
        TextField(controller: name, decoration: const InputDecoration(labelText:'Nom')),
        TextField(controller: desc, decoration: const InputDecoration(labelText:'Description')),
        DropdownButtonFormField<String>(initialValue: scope, decoration: const InputDecoration(labelText:'Portée'), items: const [DropdownMenuItem(value:'global', child:Text('Globale (établissement)')), DropdownMenuItem(value:'restricted', child:Text('Restreinte (affectations)')), DropdownMenuItem(value:'caisse', child:Text('Caisse'))], onChanged:(v)=>setState(()=>scope=v??'global')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed:() async { if(name.text.trim().isEmpty) return; await ref.read(adminRepositoryProvider).upsertRole(id: r?.id, name: name.text.trim(), description: desc.text.trim().isEmpty?null:desc.text.trim(), scope: scope); if(ctx.mounted) Navigator.pop(ctx); }, child: const Text('Enregistrer'))],
    )));
  }
}

class _AuditTab extends ConsumerWidget {
  const _AuditTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(auditLogsProvider);
    final fmt = DateFormat('dd/MM/yyyy HH:mm:ss');
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Text('Journal d\'audit', style: Theme.of(context).textTheme.titleMedium), const Spacer(), FilledButton.icon(onPressed: ()=>_export(context, ref), icon: const Icon(Icons.download), label: const Text('Exporter (JSON + SHA-256)'))]),
      const SizedBox(height: 12),
      Expanded(child: logs.when(loading: ()=>const Center(child:CircularProgressIndicator()), error:(e,_)=>Center(child:Text('Erreur: $e')), data:(list)=> list.isEmpty? const Text('Aucun événement.') : ListView.builder(itemCount:list.length,itemBuilder:(context,i){ final l=list[i]; return ListTile(dense:true, leading: Icon(l.result=='success'?Icons.check_circle_outline:Icons.error_outline, color: l.result=='success'?Colors.green:Colors.red), title: Text('${l.module} • ${l.action}'), subtitle: Text('${fmt.format(l.timestamp.toLocal())} • ${l.username ?? l.userId ?? '-'} • ${l.targetType ?? ''} ${l.targetId ?? ''}\n${l.details ?? ''}')); }))),
    ]));
  }

  static Future<void> _export(BuildContext context, WidgetRef ref) async {
    final res = await ref.read(adminRepositoryProvider).exportAuditLogs();
    if (!context.mounted) return;
    await showDialog(context: context, builder: (ctx)=>AlertDialog(
      title: const Text('Export journal d\'audit'),
      content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children:[
        const Text('Empreinte SHA-256 (intégrité du fichier JSON) :'),
        const SizedBox(height: 6),
        SelectableText(res.sha256, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        const SizedBox(height: 12),
        Text('Entrées: ${RegExp(r'"id"').allMatches(res.json).length}'),
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx), child: const Text('Fermer')),
        TextButton(onPressed:() async { await Clipboard.setData(ClipboardData(text: res.sha256)); if(ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Hash copié.'))); }, child: const Text('Copier hash')),
        FilledButton(onPressed:() async {
          final path = await FilePicker.platform.saveFile(dialogTitle: 'Enregistrer le journal (JSON)', fileName: 'audit_log.json', type: FileType.custom, allowedExtensions: ['json']);
          if (path != null) { await File(path).writeAsString(res.json); final hashPath = path.endsWith('.json') ? '${path.substring(0, path.length-5)}.sha256.txt' : '$path.sha256.txt'; await File(hashPath).writeAsString('${res.sha256}  audit_log.json\n'); if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Exporté: $path (+ hash)'))); }
        }, child: const Text('Enregistrer JSON')),
      ],
    ));
  }
}

class _AssignmentsDialog extends ConsumerWidget {
  final User user;
  const _AssignmentsDialog({required this.user});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(StreamProvider<List<TeacherAssignment>>((ref) {
      final db = ref.watch(adminRepositoryProvider).db;
      return (db.select(db.teacherAssignments)..where((t) => t.userId.equals(user.id))..where((t) => t.isDeleted.equals(false))).watch();
    }));
    final years = ref.watch(academicYearsProvider).valueOrNull ?? [];
    final yearId = years.where((y) => y.isCurrent).firstOrNull?.id ?? (years.isNotEmpty ? years.first.id : null);
    final classes = ref.watch(classesProvider(yearId)).valueOrNull ?? [];
    final classNames = {for (final c in classes) c.id: c.name};
    return AlertDialog(
      title: Text('Affectations - ${user.displayName}'),
      content: SizedBox(width: 520, height: 400, child: assignments.when(
        loading: ()=>const Center(child:CircularProgressIndicator()),
        error: (e,_)=>Text('Erreur: $e'),
        data: (list)=> Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          FilledButton.icon(onPressed: ()=>_add(context, ref, yearId), icon: const Icon(Icons.add), label: const Text('Ajouter affectation')),
          const SizedBox(height: 8),
          const Text('Portée restreinte: l\'enseignant n\'accède qu\'aux classes/matières affectées.'),
          const SizedBox(height: 8),
          Expanded(child: list.isEmpty ? const Text('Aucune affectation.') : ListView.builder(itemCount: list.length, itemBuilder: (c,i){ final a=list[i]; return ListTile(title: Text(classNames[a.classId] ?? a.classId), subtitle: Text('Année: ${a.academicYearId ?? '-'}'), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: ()=>ref.read(adminRepositoryProvider).removeAssignment(a.id))); })),
        ]),
      )),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Fermer'))],
    );
  }
  Future<void> _add(BuildContext context, WidgetRef ref, String? yearId) async {
    final classes = ref.read(classesProvider(yearId)).valueOrNull ?? [];
    if (classes.isEmpty) return;
    String classId = classes.first.id;
    await showDialog(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setState)=>AlertDialog(
      title: const Text('Nouvelle affectation'),
      content: DropdownButtonFormField<String>(initialValue: classId, items: [for (final c in classes) DropdownMenuItem(value: c.id, child: Text(c.name))], onChanged: (v)=>setState(()=>classId=v??classId), decoration: const InputDecoration(labelText: 'Classe')),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () async { await ref.read(adminRepositoryProvider).addAssignment(userId: user.id, classId: classId, academicYearId: yearId); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text('Ajouter'))],
    )));
  }
}
