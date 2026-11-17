import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/core/database/seed_importer.dart';
import 'package:fianarana/features/auth/application/auth_providers.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController(text: 'admin.sys');
  final _fullName = TextEditingController(text: 'Administrateur Système');
  final _email = TextEditingController(text: 'admin@etablissement.mg');
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _importSeeds = true;
  bool _loading = false;
  String? _message;

  @override
  void dispose() {
    _username.dispose();
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.createInitialAdmin(
        username: _username.text.trim(),
        fullName: _fullName.text.trim(),
        password: _password.text,
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      );
      if (_importSeeds) {
        final db = ref.read(appDatabaseProvider);
        final importer = SeedImporter(db);
        final result = await importer.importAll();
        _message = 'Compte administrateur créé. Données de test importées: $result';
      } else {
        _message = 'Compte administrateur créé.';
      }
      ref.invalidate(hasAnyUserProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_message ?? 'Installation terminée')),
        );
      }
    } catch (e) {
      setState(() => _message = 'Erreur: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        toolbarHeight: 48,
        title: Row(children: [
          Container(width: 28, height: 28, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1E40AF)])), child: const Icon(Icons.school, color: Colors.white, size: 16)),
          const SizedBox(width: 10),
          const Text('Première installation'),
        ]),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Container(
            decoration: BoxDecoration(color: isDark ? const Color(0xFF0F172A) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text('Assistant de configuration initiale', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text('Créez le compte Administrateur initial et importez les données de test fournies.'),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _fullName,
                      decoration: const InputDecoration(labelText: 'Nom complet'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _username,
                      decoration: const InputDecoration(labelText: 'Identifiant administrateur'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email (optionnel)'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      decoration: const InputDecoration(labelText: 'Mot de passe'),
                      obscureText: true,
                      validator: (v) => v == null || v.length < 8 ? 'Minimum 8 caractères' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirm,
                      decoration: const InputDecoration(labelText: 'Confirmer le mot de passe'),
                      obscureText: true,
                      validator: (v) => v != _password.text ? 'Les mots de passe ne correspondent pas' : null,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: _importSeeds,
                      onChanged: (v) => setState(() => _importSeeds = v),
                      title: const Text('Importer les données de test (recommandé)'),
                      subtitle: const Text('Établissement, 325 élèves, classes, personnel, finances, notes, etc. depuis donnees_de_test.xlsx'),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 8),
                      Text(_message!),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: _loading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: const Text('Terminer l’installation'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
