import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/routing/app_router.dart';
import 'package:fianarana/core/theme/app_theme.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';

class FianaranaApp extends ConsumerWidget {
  const FianaranaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final auth = ref.watch(authControllerProvider);

    return MaterialApp.router(
      title: 'Fianarana - Gestion scolaire',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) {
        return Shortcuts(
          shortcuts: <LogicalKeySet, Intent>{
            LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyL): const _LockIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _LockIntent: CallbackAction<_LockIntent>(onInvoke: (_) {
                ref.read(authControllerProvider.notifier).lock();
                return null;
              }),
            },
            child: Stack(
              children: [
                if (child != null) child,
                if (auth.isAuthenticated && auth.isLocked)
                  _LockOverlay(onUnlock: (pwd) => ref.read(authControllerProvider.notifier).unlockWithPassword(pwd)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LockIntent extends Intent {
  const _LockIntent();
}

class _LockOverlay extends StatefulWidget {
  final Future<bool> Function(String password) onUnlock;
  const _LockOverlay({required this.onUnlock});
  @override
  State<_LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends State<_LockOverlay> {
  final _ctrl = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    setState(() { _busy = true; _err = null; });
    final ok = await widget.onUnlock(_ctrl.text);
    if (!mounted) return;
    setState(() { _busy = false; _err = ok ? null : 'Mot de passe/PIN invalide'; });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black54,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock, size: 40),
                  const SizedBox(height: 8),
                  const Text('Session verrouillée (Ctrl+L)'),
                  const SizedBox(height: 12),
                  TextField(controller: _ctrl, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe pour déverrouiller'), onSubmitted: (_) => _submit()),
                  if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _busy ? null : _submit, child: const Text('Déverrouiller')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
