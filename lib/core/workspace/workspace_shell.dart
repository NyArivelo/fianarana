import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fianarana/core/workspace/tab_workspace.dart';

/// Shell MDI fondation: barre d'onglets de travail + contenu.
/// Les modules peuvent ouvrir des onglets via tabWorkspaceProvider.openTab(...).
class WorkspaceShell extends ConsumerWidget {
  final Widget child;
  const WorkspaceShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(tabWorkspaceProvider);
    // Si aucun onglet géré, on affiche le contenu routé normalement.
    if (ws.tabs.isEmpty) return child;

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: ws.tabs.length,
                    itemBuilder: (context, i) {
                      final t = ws.tabs[i];
                      final active = i == ws.activeIndex;
                      return InkWell(
                        onTap: () => ref.read(tabWorkspaceProvider.notifier).activate(i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: active ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 2)),
                          ),
                          child: Row(children: [
                            Text(t.title),
                            const SizedBox(width: 6),
                            InkWell(onTap: () => ref.read(tabWorkspaceProvider.notifier).closeTab(t.id), child: const Icon(Icons.close, size: 14)),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
                IconButton(tooltip: 'Fermer l\'onglet (Ctrl+W)', icon: const Icon(Icons.tab_close), onPressed: () => ref.read(tabWorkspaceProvider.notifier).closeActive()),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: ws.tabs[ws.activeIndex].builder(context)),
      ],
    );
  }
}

/// Helper: ouvrir un module comme onglet de travail.
void openModuleTab(WidgetRef ref, {required String id, required String title, required String route, required WidgetBuilder builder}) {
  ref.read(tabWorkspaceProvider.notifier).openTab(WorkspaceTab(id: id, title: title, route: route, builder: builder));
}
