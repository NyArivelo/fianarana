import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/core/routing/app_router.dart';
import 'package:fianarana/core/services/backup_service.dart';
import 'package:fianarana/core/theme/app_theme.dart';
import 'package:fianarana/core/workspace/tab_workspace.dart';
import 'package:fianarana/core/workspace/workspace_shell.dart';
import 'package:fianarana/features/auth/application/auth_controller.dart';
import 'package:fianarana/features/search/presentation/global_search_dialog.dart';

class FianaranaApp extends ConsumerStatefulWidget {
  const FianaranaApp({super.key});
  @override
  ConsumerState<FianaranaApp> createState() => _FianaranaAppState();
}

class _FianaranaAppState extends ConsumerState<FianaranaApp> with WidgetsBindingObserver {
  Timer? _inactivity;
  Timer? _autoBackup;
  static const _inactivityTimeout = Duration(minutes: 5);
  static const _autoBackupInterval = Duration(hours: 12);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetInactivity();
    _startAutoBackup();
  }

  void _startAutoBackup() {
    _autoBackup?.cancel();
    _autoBackup = Timer.periodic(_autoBackupInterval, (_) {
      final db = ref.read(appDatabaseProvider);
      final auth = ref.read(authControllerProvider);
      if (auth.isAuthenticated) {
        BackupService(db).createBackup(type: 'auto-planifiee', actorUserId: auth.userId, actorUsername: auth.username);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivity?.cancel();
    _autoBackup?.cancel();
    super.dispose();
  }

  void _resetInactivity() {
    _inactivity?.cancel();
    _inactivity = Timer(_inactivityTimeout, () {
      final auth = ref.read(authControllerProvider);
      if (auth.isAuthenticated && !auth.isLocked) {
        ref.read(authControllerProvider.notifier).lock();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sauvegarde auto à la fermeture/mise en arrière-plan (fondation)
    if (state == AppLifecycleState.detached || state == AppLifecycleState.paused) {
      final db = ref.read(appDatabaseProvider);
      final auth = ref.read(authControllerProvider);
      BackupService(db).createBackup(type: 'auto', actorUserId: auth.userId, actorUsername: auth.username);
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final auth = ref.watch(authControllerProvider);

    return Listener(
      onPointerDown: (_) => _resetInactivity(),
      onPointerMove: (_) => _resetInactivity(),
      onPointerSignal: (_) => _resetInactivity(),
      child: MaterialApp.router(
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
              LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyW): const _CloseTabIntent(),
              LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF): const _SearchIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _LockIntent: CallbackAction<_LockIntent>(onInvoke: (_) {
                  ref.read(authControllerProvider.notifier).lock();
                  return null;
                }),
                _CloseTabIntent: CallbackAction<_CloseTabIntent>(onInvoke: (_) {
                  final ws = ref.read(tabWorkspaceProvider);
                  if (ws.tabs.isNotEmpty) {
                    ref.read(tabWorkspaceProvider.notifier).closeActive();
                  } else {
                    router.pop();
                  }
                  return null;
                }),
                _SearchIntent: CallbackAction<_SearchIntent>(onInvoke: (_) {
                  final ctx = router.routerDelegate.navigatorKey.currentContext;
                  if (ctx != null) showGlobalSearch(ctx);
                  return null;
                }),
              },
              child: Material(
                color: Colors.transparent,
                child: Stack(
                  children: [
                    if (child != null) WorkspaceShell(child: child),
                    if (auth.isAuthenticated && auth.isLocked)
                      _LockOverlay(
                        onUnlockPassword: (pwd) => ref.read(authControllerProvider.notifier).unlockWithPassword(pwd),
                        onUnlockPin: (pin) => ref.read(authControllerProvider.notifier).unlockWithPin(pin),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LockIntent extends Intent { const _LockIntent(); }
class _CloseTabIntent extends Intent { const _CloseTabIntent(); }
class _SearchIntent extends Intent { const _SearchIntent(); }

class _LockOverlay extends StatefulWidget {
  final Future<bool> Function(String password) onUnlockPassword;
  final Future<bool> Function(String pin) onUnlockPin;
  const _LockOverlay({required this.onUnlockPassword, required this.onUnlockPin});
  @override
  State<_LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends State<_LockOverlay> {
  final _ctrl = TextEditingController();
  String? _err;
  bool _busy = false;
  bool _usePin = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    setState(() { _busy = true; _err = null; });
    final ok = _usePin ? await widget.onUnlockPin(_ctrl.text.trim()) : await widget.onUnlockPassword(_ctrl.text);
    if (!mounted) return;
    setState(() { _busy = false; _err = ok ? null : (_usePin ? 'PIN invalide' : 'Mot de passe invalide'); });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black54,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock, size: 40),
                  const SizedBox(height: 8),
                  const Text('Session verrouillée (Ctrl+L / inactivité)'),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Mot de passe')),
                      ButtonSegment(value: true, label: Text('PIN rapide')),
                    ],
                    selected: {_usePin},
                    onSelectionChanged: (s) => setState(() { _usePin = s.first; _ctrl.clear(); _err = null; }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ctrl,
                    obscureText: true,
                    keyboardType: _usePin ? TextInputType.number : TextInputType.text,
                    maxLength: _usePin ? 6 : null,
                    decoration: InputDecoration(labelText: _usePin ? 'PIN (4-6 chiffres)' : 'Mot de passe'),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_err != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 8),
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
