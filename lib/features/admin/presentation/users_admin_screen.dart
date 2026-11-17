import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/admin/data/admin_repository.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';

final _adminRepoProvider = Provider((ref)=>AdminRepository(ref.watch(appDatabaseProvider)));

class UsersAdminScreen extends ConsumerStatefulWidget {
  const UsersAdminScreen({super.key});
  @override
  ConsumerState<UsersAdminScreen> createState() => _UsersAdminScreenState();
}

class _UsersAdminScreenState extends ConsumerState<UsersAdminScreen> {
  Future<void> _editUser([dynamic u]) async {
    final auth = ref.read(authControllerProvider);
    final repo = ref.read(_adminRepoProvider);
    final roles = await repo.listRoles(actorUserId: auth.userId);
    final selectedRoles = u == null ? <String>{} : (await repo.roleIdsOfUser(u.id as String)).toSet();
    if (!mounted) return;
    final username = TextEditingController(text: u?.username ?? '');
    final fullName = TextEditingController(text: u?.fullName ?? '');
    final email = TextEditingController(text: u?.email ?? '');
    final pass = TextEditingController();
    final pin = TextEditingController();
    String scope = u?.scopeType ?? 'Globale';
    bool active = u?.isActive ?? true;
    final ok = await showDialog<bool>(context: context, builder: (ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title: Text(u==null?'Nouvel utilisateur':'Modifier utilisateur'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children:[
        TextField(controller: username, decoration: const InputDecoration(labelText: 'Identifiant')),
        TextField(controller: fullName, decoration: const InputDecoration(labelText: 'Nom complet')),
        TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
        if (u==null) TextField(controller: pass, decoration: const InputDecoration(labelText: 'Mot de passe initial'), obscureText: true),
        TextField(controller: pin, decoration: const InputDecoration(labelText: 'PIN rapide (4-6 chiffres, optionnel)'), obscureText: true),
        DropdownButtonFormField<String>(value: scope, decoration: const InputDecoration(labelText: 'Portée (scope)'), items: const ['Globale','Affectations','Caisse'].map((s)=>DropdownMenuItem(value:s, child: Text(s))).toList(), onChanged: (v)=>setD(()=>scope=v??'Globale')),
        SwitchListTile(value: active, onChanged: (v)=>setD(()=>active=v), title: const Text('Compte actif')),
        const SizedBox(height: 8), const Text('Rôles', style: TextStyle(fontWeight: FontWeight.w600)),
        Wrap(spacing: 6, children: roles.map((r)=>FilterChip(label: Text(r.name), selected: selectedRoles.contains(r.id), onSelected: (v)=>setD(()=> v?selectedRoles.add(r.id):selectedRoles.remove(r.id)))).toList()),
      ]))),
      actions:[TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Annuler')), FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Enregistrer'))],
    )));
    if (ok==true) {
      try {
        await repo.upsertUser(id: u?.id, username: username.text.trim(), fullName: fullName.text.trim(), email: email.text.trim().isEmpty?null:email.text.trim(), password: pass.text.isEmpty?null:pass.text, pin: pin.text.trim().isEmpty?null:pin.text.trim(), isActive: active, scopeType: scope, actorUserId: auth.userId, actorUsername: auth.username);
        final uid = u?.id ?? (await repo.listUsers(actorUserId: auth.userId)).firstWhere((x)=>x.username==username.text.trim()).id;
        await repo.setUserRoles(uid, selectedRoles.toList(), actorUserId: auth.userId, actorUsername: auth.username);
        setState((){});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Utilisateur enregistré.')));
      } catch(e){ if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'))); }
    }
  }

  Future<void> _resetPwd(dynamic u) async {
    final auth = ref.read(authControllerProvider);
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx)=>AlertDialog(title: const Text('Réinitialiser le mot de passe'), content: TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(labelText: 'Nouveau mot de passe')), actions:[TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Annuler')), FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Réinitialiser'))]));
    if (ok==true && ctrl.text.isNotEmpty) {
      await ref.read(_adminRepoProvider).resetPassword(u.id as String, ctrl.text, actorUserId: auth.userId, actorUsername: auth.username);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mot de passe réinitialisé.')));
    }
  }

  Future<void> _editRolePermissions() async {
    final auth = ref.read(authControllerProvider);
    final repo = ref.read(_adminRepoProvider);
    final roles = await repo.listRoles(actorUserId: auth.userId);
    final perms = await repo.listPermissions(actorUserId: auth.userId);
    if (!mounted || roles.isEmpty) return;
    String roleId = roles.first.id;
    Set<String> selected = await repo.permissionIdsOfRole(roleId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: const Text('Permissions par rôle'),
        content: SizedBox(width: 760, height: 560, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownButtonFormField<String>(
            value: roleId,
            decoration: const InputDecoration(labelText: 'Rôle'),
            items: roles.map((r)=>DropdownMenuItem(value: r.id, child: Text(r.name))).toList(),
            onChanged: (v) async {
              if (v == null) return;
              final s = await repo.permissionIdsOfRole(v);
              setD(() { roleId = v; selected = s; });
            },
          ),
          const SizedBox(height: 8),
          const Text('Cochez les permissions accordées au rôle sélectionné.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Expanded(child: ListView(
            children: perms.map((p) => CheckboxListTile(
              dense: true,
              value: selected.contains(p.id),
              onChanged: (v) => setD(() => v == true ? selected.add(p.id) : selected.remove(p.id)),
              title: Text(p.code, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              subtitle: Text('${p.module} • ${p.action}${p.description != null ? " — ${p.description}" : ""}', style: const TextStyle(fontSize: 11)),
              controlAffinity: ListTileControlAffinity.leading,
            )).toList(),
          )),
        ])),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Fermer')),
          FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Enregistrer')),
        ],
      )),
    );
    if (ok == true) {
      try {
        await repo.setRolePermissions(roleId, selected, actorUserId: auth.userId, actorUsername: auth.username);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permissions du rôle mises à jour.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final repo = ref.watch(_adminRepoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Utilisateurs & rôles (administration)'), actions:[
        OutlinedButton.icon(onPressed: _editRolePermissions, icon: const Icon(Icons.security, size:16), label: const Text('Permissions rôles')),
        const SizedBox(width: 8),
        FilledButton.icon(onPressed: ()=>_editUser(), icon: const Icon(Icons.person_add, size:16), label: const Text('Nouvel utilisateur')),
        const SizedBox(width:12),
      ]),
      body: FutureBuilder(
        future: repo.listUsers(actorUserId: auth.userId),
        builder: (c, snap) {
          if (!snap.hasData) return snap.hasError ? Center(child: Text('Erreur: ${snap.error}')) : const Center(child: CircularProgressIndicator());
          final users = snap.data!;
          return ListView.builder(itemCount: users.length, itemBuilder: (c,i){ final u=users[i]; return ListTile(
            leading: Icon(u.isActive ? Icons.person : Icons.person_off_outlined),
            title: Text('${u.fullName} (${u.username})'),
            subtitle: Text('Portée: ${u.scopeType} • ${u.isActive ? "Actif" : "Désactivé"}${u.lockedUntil!=null?" • Verrouillé":""}'),
            trailing: Wrap(spacing:4, children:[
              IconButton(tooltip:'Modifier', onPressed: ()=>_editUser(u), icon: const Icon(Icons.edit_outlined)),
              IconButton(tooltip:'Réinitialiser mot de passe', onPressed: ()=>_resetPwd(u), icon: const Icon(Icons.lock_reset)),
              IconButton(tooltip: u.isActive?'Désactiver':'Réactiver', onPressed: () async { try { await repo.toggleActive(u.id, !u.isActive, actorUserId: auth.userId, actorUsername: auth.username); setState((){});} catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));} }, icon: Icon(u.isActive?Icons.block:Icons.check_circle_outline)),
            ]),
          ); });
        },
      ),
    );
  }
}
