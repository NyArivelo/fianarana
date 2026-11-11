import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});
  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _password = TextEditingController();
  final _pin = TextEditingController();
  final _switchUser = TextEditingController();
  final _switchPin = TextEditingController();
  String? _error;

  @override
  void dispose() { _password.dispose(); _pin.dispose(); _switchUser.dispose(); _switchPin.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.currentUser;
    return Positioned.fill(child: Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Card(child: Padding(padding: const EdgeInsets.all(24), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.lock, size: 40),
        const SizedBox(height: 8),
        Text('Session verrouillée', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
        if (user != null) Text('Utilisateur: ${user.displayName} (${user.username})', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe (déverrouiller)'), onSubmitted: (_) => _unlockPassword()),
        const SizedBox(height: 8),
        FilledButton(onPressed: _unlockPassword, child: const Text('Déverrouiller avec mot de passe')),
        const SizedBox(height: 12),
        TextField(controller: _pin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Code PIN (4-6 chiffres)'), onSubmitted: (_) => _unlockPin()),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _unlockPin, child: const Text('Déverrouiller avec PIN')),
        const Divider(height: 28),
        Text('Changement rapide d’utilisateur (PIN)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(controller: _switchUser, decoration: const InputDecoration(labelText: 'Identifiant')),
        const SizedBox(height: 8),
        TextField(controller: _switchPin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Code PIN')),
        const SizedBox(height: 8),
        FilledButton.tonal(onPressed: _quickSwitch, child: const Text('Basculer (Quick Switch)')),
        const SizedBox(height: 12),
        TextButton(onPressed: () => ref.read(authControllerProvider.notifier).logout(), child: const Text('Se déconnecter')),
        if (_error != null || auth.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error ?? auth.error!, style: const TextStyle(color: Colors.red))),
      ])))))),
    ));
  }

  Future<void> _unlockPassword() async {
    setState(()=>_error=null);
    final ok = await ref.read(authControllerProvider.notifier).unlockWithPassword(_password.text);
    if (!ok && mounted) setState(()=>_error = ref.read(authControllerProvider).error ?? 'Échec du déverrouillage.');
  }
  Future<void> _unlockPin() async {
    setState(()=>_error=null);
    final ok = await ref.read(authControllerProvider.notifier).unlockWithPin(_pin.text.trim());
    if (!ok && mounted) setState(()=>_error = ref.read(authControllerProvider).error ?? 'Échec du déverrouillage.');
  }
  Future<void> _quickSwitch() async {
    setState(()=>_error=null);
    final ok = await ref.read(authControllerProvider.notifier).quickSwitchWithPin(_switchUser.text.trim(), _switchPin.text.trim());
    if (!ok && mounted) setState(()=>_error = ref.read(authControllerProvider).error ?? 'Échec du changement d’utilisateur.');
  }
}
