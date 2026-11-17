import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fianarana/core/database/app_database.dart';
import 'package:fianarana/core/database/database_provider.dart';
import 'package:fianarana/features/attendance/presentation/attendance_screen.dart';
import 'package:fianarana/features/calendar/presentation/calendar_screen.dart';
import 'package:fianarana/features/dashboard/presentation/dashboard_screen.dart';
import 'package:fianarana/features/documents/presentation/document_studio_screen.dart';
import 'package:fianarana/features/facilities/presentation/facilities_screen.dart';
import 'package:fianarana/features/finance/presentation/finance_screen.dart';
import 'package:fianarana/features/finance/presentation/schedules_screen.dart';
import 'package:fianarana/features/grades/presentation/councils_screen.dart';
import 'package:fianarana/features/grades/presentation/grades_screen.dart';
import 'package:fianarana/features/library/presentation/library_screen.dart';
import 'package:fianarana/features/settings/presentation/settings_screen.dart';
import 'package:fianarana/features/staff/presentation/staff_screen.dart';
import 'package:fianarana/features/students/presentation/student_detail_screen.dart';
import 'package:fianarana/features/students/presentation/students_screen.dart';
import 'package:fianarana/features/timetable/presentation/timetable_screen.dart';
import 'package:fianarana/features/admin/presentation/users_admin_screen.dart';

const kMdiWorkspaceTabsKey = 'mdi_workspace_tabs';

class WorkspaceTab {
  final String id;
  final String title;
  final String route;
  final WidgetBuilder builder;
  bool dirty;
  WorkspaceTab({required this.id, required this.title, required this.route, required this.builder, this.dirty = false});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'route': route};
}

class TabWorkspaceState {
  final List<WorkspaceTab> tabs;
  final int activeIndex;
  final bool restored;
  const TabWorkspaceState({this.tabs = const [], this.activeIndex = 0, this.restored = false});

  TabWorkspaceState copyWith({List<WorkspaceTab>? tabs, int? activeIndex, bool? restored}) => TabWorkspaceState(
      tabs: tabs ?? this.tabs, activeIndex: activeIndex ?? this.activeIndex, restored: restored ?? this.restored);
}

class TabWorkspaceController extends StateNotifier<TabWorkspaceState> {
  final Future<void> Function(TabWorkspaceState)? onPersist;
  TabWorkspaceController({this.onPersist}) : super(const TabWorkspaceState());

  void _emit(TabWorkspaceState next) {
    state = next;
    onPersist?.call(next);
  }

  void openTab(WorkspaceTab tab) {
    final idx = state.tabs.indexWhere((t) => t.id == tab.id || t.route == tab.route);
    if (idx >= 0) {
      _emit(state.copyWith(activeIndex: idx));
      return;
    }
    final next = [...state.tabs, tab];
    _emit(TabWorkspaceState(tabs: next, activeIndex: next.length - 1, restored: state.restored));
  }

  void closeTab(String id) {
    final idx = state.tabs.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final next = [...state.tabs]..removeAt(idx);
    var active = state.activeIndex;
    if (next.isEmpty) {
      _emit(TabWorkspaceState(restored: state.restored));
      return;
    }
    if (active >= next.length) active = next.length - 1;
    if (idx < active) active -= 1;
    _emit(TabWorkspaceState(tabs: next, activeIndex: active, restored: state.restored));
  }

  void closeActive() {
    if (state.tabs.isEmpty) return;
    closeTab(state.tabs[state.activeIndex].id);
  }

  void activate(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    _emit(state.copyWith(activeIndex: index));
  }

  void restore(List<WorkspaceTab> tabs, int activeIndex) {
    if (tabs.isEmpty) {
      state = TabWorkspaceState(restored: true);
      return;
    }
    final idx = activeIndex.clamp(0, tabs.length - 1);
    state = TabWorkspaceState(tabs: tabs, activeIndex: idx, restored: true);
  }
}

WorkspaceTab? buildTabForRoute(String route) {
  final uri = Uri.tryParse(route) ?? Uri(path: route);
  final path = uri.path.isEmpty ? '/' : uri.path;
  String title;
  WidgetBuilder builder;

  if (path == '/') {
    title = 'Tableau de bord';
    builder = (_) => const DashboardScreen();
  } else if (path == '/students') {
    title = 'Élèves & Inscriptions';
    builder = (_) => const StudentsScreen();
  } else if (path == '/students/new') {
    title = 'Nouvel élève';
    builder = (_) => const StudentDetailScreen(studentId: 'new');
  } else if (path.startsWith('/students/')) {
    final id = path.split('/').last;
    title = 'Élève';
    builder = (_) => StudentDetailScreen(studentId: id);
  } else if (path == '/attendance') {
    title = 'Présences & Discipline';
    builder = (_) => const AttendanceScreen();
  } else if (path == '/finance') {
    title = 'Finances & Caisse';
    builder = (_) => const FinanceScreen();
  } else if (path == '/finance/schedules') {
    title = 'Échéanciers';
    builder = (_) => const SchedulesScreen();
  } else if (path == '/grades') {
    title = 'Évaluations & Notes';
    builder = (_) => const GradesScreen();
  } else if (path == '/grades/councils') {
    title = 'Conseils de classe';
    builder = (_) => const CouncilsScreen();
  } else if (path == '/timetable') {
    title = 'Emplois du temps';
    final c = uri.queryParameters['class'];
    final t = uri.queryParameters['teacher'];
    builder = (_) => TimetableScreen(initialClassId: c, initialTeacherId: t);
  } else if (path == '/calendar') {
    title = 'Calendrier & Éphéméride';
    builder = (_) => const CalendarScreen();
  } else if (path == '/documents') {
    title = 'Document Studio';
    builder = (_) => const DocumentStudioScreen();
  } else if (path == '/settings') {
    title = 'Paramètres';
    builder = (_) => const SettingsScreen();
  } else if (path == '/settings/users') {
    title = 'Utilisateurs & rôles';
    builder = (_) => const UsersAdminScreen();
  } else if (path == '/staff') {
    title = 'Personnel & RH';
    builder = (_) => const StaffScreen();
  } else if (path == '/library') {
    title = 'Bibliothèque & Quitus';
    builder = (_) => const LibraryScreen();
  } else if (path == '/facilities') {
    title = 'Locaux & Équipements';
    builder = (_) => const FacilitiesScreen();
  } else {
    return null;
  }
  final id = route; // route complète comme identifiant stable (inclut contexte)
  return WorkspaceTab(id: id, title: title, route: route, builder: builder);
}

String encodeWorkspaceState(TabWorkspaceState state) {
  return jsonEncode({
    'activeIndex': state.activeIndex,
    'tabs': state.tabs.map((t) => t.toJson()).toList(),
  });
}

Future<void> _persistWorkspace(AppDatabase db, TabWorkspaceState state) async {
  try {
    await db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: kMdiWorkspaceTabsKey, value: Value(encodeWorkspaceState(state))));
  } catch (_) {}
}

Future<List<WorkspaceTab>> _loadPersistedTabs(AppDatabase db) async {
  try {
    final row = await (db.select(db.appSettings)..where((t) => t.key.equals(kMdiWorkspaceTabsKey))).getSingleOrNull();
    final raw = row?.value;
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    final list = decoded['tabs'];
    if (list is! List) return const [];
    final tabs = <WorkspaceTab>[];
    for (final e in list) {
      if (e is! Map) continue;
      final route = (e['route'] ?? '').toString();
      if (route.isEmpty) continue;
      final tab = buildTabForRoute(route);
      if (tab != null) {
        // garder titre/id persistés si fournis
        final title = (e['title'] ?? tab.title).toString();
        tabs.add(WorkspaceTab(id: route, title: title, route: route, builder: tab.builder));
      }
    }
    return tabs;
  } catch (_) {
    return const [];
  }
}

final tabWorkspaceProvider = StateNotifierProvider<TabWorkspaceController, TabWorkspaceState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final controller = TabWorkspaceController(onPersist: (s) => _persistWorkspace(db, s));
  // restauration async de l'état MDI (onglets/contexte)
  () async {
    final tabs = await _loadPersistedTabs(db);
    int active = 0;
    try {
      final row = await (db.select(db.appSettings)..where((t) => t.key.equals(kMdiWorkspaceTabsKey))).getSingleOrNull();
      final raw = row?.value;
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) active = (decoded['activeIndex'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    if (tabs.isNotEmpty) controller.restore(tabs, active);
    else controller.state = controller.state.copyWith(restored: true);
  }();
  return controller;
});

/// Helper: ouvrir un module comme onglet de travail (et persister).
void openModuleTab(WidgetRef ref,
    {required String id,
    required String title,
    required String route,
    required WidgetBuilder builder}) {
  ref.read(tabWorkspaceProvider.notifier).openTab(
      WorkspaceTab(id: id, title: title, route: route, builder: builder));
}

/// Ouvre/active un onglet pour une route applicative connue (restauration/navigation MDI).
bool openRouteTab(WidgetRef ref, String route) {
  final tab = buildTabForRoute(route);
  if (tab == null) return false;
  ref.read(tabWorkspaceProvider.notifier).openTab(tab);
  return true;
}
