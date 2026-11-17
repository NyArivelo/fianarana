import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/core/services/recycle_bin_service.dart';
import 'package:fianarana/core/settings/app_config.dart';
import 'package:fianarana/core/routing/app_router.dart';
import 'package:fianarana/core/services/backup_service.dart';
import 'package:fianarana/core/settings/ui_settings.dart';
import 'package:fianarana/core/theme/app_theme.dart';
import 'package:fianarana/core/workspace/tab_workspace.dart';
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
  Duration _inactivityTimeout = const Duration(minutes: 5);
  bool _autoBackupEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetInactivity();
    _loadConfigAndMaintenance();
  }

  Future<void> _loadConfigAndMaintenance() async {
    try {
      final cfg = await ref.read(appConfigProvider.future);
      if (mounted) {
        setState(() => _inactivityTimeout = Duration(minutes: cfg.inactivityMinutes));
        _autoBackupEnabled = cfg.autoBackupEnabled;
        _startAutoBackup(intervalHours: cfg.autoBackupIntervalHours, enabled: cfg.autoBackupEnabled);
        final db = ref.read(appDatabaseProvider);
        await RecycleBinService(db).purgeOlderThan(Duration(days: cfg.recycleRetentionDays));
      }
    } catch (_) {}
  }

  void _startAutoBackup({required int intervalHours, required bool enabled}) {
    _autoBackup?.cancel();
    _autoBackupEnabled = enabled;
    if (!enabled) return;
    _autoBackup = Timer.periodic(Duration(hours: intervalHours.clamp(1, 168)), (_) async {
      try {
        if (!_autoBackupEnabled) return;
        final db = ref.read(appDatabaseProvider);
        final auth = ref.read(authControllerProvider);
        if (auth.isAuthenticated) {
          await BackupService(db).createBackup(
              type: 'auto-planifiee',
              actorUserId: auth.userId,
              actorUsername: auth.username);
        }
      } catch (_) {
        // Échec sauvegarde planifiée : tracé dans le service.
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
    // Sauvegarde auto à la fermeture/mise en arrière-plan (si activée)
    if (state == AppLifecycleState.detached || state == AppLifecycleState.paused) {
      if (!_autoBackupEnabled) return;
      final db = ref.read(appDatabaseProvider);
      final auth = ref.read(authControllerProvider);
      BackupService(db)
          .createBackup(type: 'auto', actorUserId: auth.userId, actorUsername: auth.username)
          .then((_) {}, onError: (_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final auth = ref.watch(authControllerProvider);
    final uiScale = ref.watch(uiScaleProvider).valueOrNull ?? kDefaultUiScale;

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
          final mq = MediaQuery.of(context);
          child = MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(uiScale)),
            child: child ?? const SizedBox.shrink(),
          );
          return Shortcuts(
            shortcuts: <LogicalKeySet, Intent>{
              LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyL): const _LockIntent(),
              LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyW): const _CloseTabIntent(),
              LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF): const _SearchIntent(),
              LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN): const _NewIntent(),
              LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS): const _SaveIntent(),
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
                _NewIntent: CallbackAction<_NewIntent>(onInvoke: (_) {
                  final loc = router.routeInformationProvider.value.uri.path;
                  if (loc.startsWith('/students')) {
                    router.go('/students/new');
                  } else if (loc.startsWith('/staff')) {
                    // écran personnel propose un bouton "Nouveau"
                    ScaffoldMessenger.maybeOf(router.routerDelegate.navigatorKey.currentContext!)?.showSnackBar(
                      const SnackBar(content: Text('Utilisez le bouton "Nouveau" dans le module Personnel.')),
                    );
                  } else if (loc.startsWith('/finance')) {
                    ScaffoldMessenger.maybeOf(router.routerDelegate.navigatorKey.currentContext!)?.showSnackBar(
                      const SnackBar(content: Text('Utilisez "Encaissement" pour créer un nouvel enregistrement financier.')),
                    );
                  } else if (loc.startsWith('/timetable')) {
                    ScaffoldMessenger.maybeOf(router.routerDelegate.navigatorKey.currentContext!)?.showSnackBar(
                      const SnackBar(content: Text('Utilisez "Nouvelle séance" dans l\'emploi du temps.')),
                    );
                  } else {
                    ScaffoldMessenger.maybeOf(router.routerDelegate.navigatorKey.currentContext!)?.showSnackBar(
                      const SnackBar(content: Text('Ctrl+N : aucun nouvel enregistrement disponible pour ce module.')),
                    );
                  }
                  return null;
                }),
                _SaveIntent: CallbackAction<_SaveIntent>(onInvoke: (_) {
                  // Raccourci global : les formulaires gèrent la sauvegarde via leurs actions/boutons.
                  ScaffoldMessenger.maybeOf(router.routerDelegate.navigatorKey.currentContext!)?.showSnackBar(
                    const SnackBar(content: Text('Ctrl+S : utilisez le bouton Enregistrer du formulaire actif.')),
                  );
                  return null;
                }),
              },
              child: Material(
                color: Colors.transparent,
                child: Stack(
                  children: [
                    if (child != null) child,
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
class _NewIntent extends Intent { const _NewIntent(); }
class _SaveIntent extends Intent { const _SaveIntent(); }

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    return Positioned.fill(
      child: Material(
        color: const Color(0xFF020617).withOpacity(0.75),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 30, offset: const Offset(0, 12))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(color: const Color(0xFF2563EB).withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFBFDBFE))),
                child: const Icon(Icons.shield_outlined, color: Color(0xFF2563EB), size: 26),
              ),
              const SizedBox(height: 12),
              Text('Session verrouillée', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF0F172A))),
              const SizedBox(height: 4),
              Text('Vos onglets sont conservés. Déverrouillez avec votre mot de passe ou code PIN.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Mot de passe'), icon: Icon(Icons.password, size: 16)),
                  ButtonSegment(value: true, label: Text('PIN rapide'), icon: Icon(Icons.pin_outlined, size: 16)),
                ],
                selected: {_usePin},
                onSelectionChanged: (s) => setState(() { _usePin = s.first; _ctrl.clear(); _err = null; }),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ctrl,
                obscureText: true,
                textAlign: _usePin ? TextAlign.center : TextAlign.start,
                style: _usePin ? const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w600) : null,
                keyboardType: _usePin ? TextInputType.number : TextInputType.text,
                maxLength: _usePin ? 6 : null,
                decoration: InputDecoration(labelText: _usePin ? 'Code PIN' : 'Mot de passe', counterText: ''),
                onSubmitted: (_) => _submit(),
              ),
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)))),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: FilledButton.icon(onPressed: _busy ? null : _submit, icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.lock_open, size: 18), label: const Text('Déverrouiller')),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
