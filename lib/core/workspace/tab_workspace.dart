import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkspaceTab {
  final String id;
  final String title;
  final String route;
  final WidgetBuilder builder;
  bool dirty;
  WorkspaceTab({required this.id, required this.title, required this.route, required this.builder, this.dirty = false});
}

class TabWorkspaceState {
  final List<WorkspaceTab> tabs;
  final int activeIndex;
  const TabWorkspaceState({this.tabs = const [], this.activeIndex = 0});

  TabWorkspaceState copyWith({List<WorkspaceTab>? tabs, int? activeIndex}) =>
      TabWorkspaceState(tabs: tabs ?? this.tabs, activeIndex: activeIndex ?? this.activeIndex);
}

class TabWorkspaceController extends StateNotifier<TabWorkspaceState> {
  TabWorkspaceController() : super(const TabWorkspaceState());

  void openTab(WorkspaceTab tab) {
    final idx = state.tabs.indexWhere((t) => t.id == tab.id);
    if (idx >= 0) {
      state = state.copyWith(activeIndex: idx);
      return;
    }
    final next = [...state.tabs, tab];
    state = TabWorkspaceState(tabs: next, activeIndex: next.length - 1);
  }

  void closeTab(String id) {
    final idx = state.tabs.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final next = [...state.tabs]..removeAt(idx);
    var active = state.activeIndex;
    if (next.isEmpty) {
      state = const TabWorkspaceState();
      return;
    }
    if (active >= next.length) active = next.length - 1;
    if (idx < active) active -= 1;
    state = TabWorkspaceState(tabs: next, activeIndex: active);
  }

  void closeActive() {
    if (state.tabs.isEmpty) return;
    closeTab(state.tabs[state.activeIndex].id);
  }

  void activate(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    state = state.copyWith(activeIndex: index);
  }
}

final tabWorkspaceProvider = StateNotifierProvider<TabWorkspaceController, TabWorkspaceState>((ref) => TabWorkspaceController());
