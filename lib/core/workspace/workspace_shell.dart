import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    if (ws.tabs.isEmpty) {
      return Material(
        color: Colors.transparent,
        child: child,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0).withOpacity(0.7);
    final border = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          Container(
            height: 38,
            decoration: BoxDecoration(color: barBg, border: Border(bottom: BorderSide(color: border))),
            padding: const EdgeInsets.only(left: 6, right: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: ws.tabs.length,
                    itemBuilder: (context, i) {
                      final t = ws.tabs[i];
                      final active = i == ws.activeIndex;
                      final tabBg = active ? (isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC)) : Colors.transparent;
                      final tabBorder = active ? border : Colors.transparent;
                      return Padding(
                        padding: const EdgeInsets.only(top: 4, right: 2),
                        child: GestureDetector(
                          onSecondaryTapDown: (details) async {
                            final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
                            final pos = overlay == null ? details.globalPosition : overlay.localToGlobal(details.globalPosition);
                            final action = await showMenu<String>(
                              context: context,
                              position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
                              items: [
                                const PopupMenuItem(value: 'close', child: Text('Fermer')),
                                const PopupMenuItem(value: 'close_others', child: Text('Fermer les autres')),
                                PopupMenuItem(value: 'close_right', enabled: i < ws.tabs.length - 1, child: const Text('Fermer à droite')),
                                const PopupMenuItem(value: 'close_all', child: Text('Fermer tout')),
                              ],
                            );
                            if (action == null) return;
                            final notifier = ref.read(tabWorkspaceProvider.notifier);
                            switch (action) {
                              case 'close':
                                notifier.closeTab(t.id);
                                break;
                              case 'close_others':
                                notifier.closeOthers(t.id);
                                break;
                              case 'close_right':
                                notifier.closeToRight(i);
                                break;
                              case 'close_all':
                                notifier.closeAll();
                                break;
                            }
                          },
                          child: InkWell(
                            onTap: () => ref.read(tabWorkspaceProvider.notifier).activate(i),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: tabBg,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                border: Border(top: BorderSide(color: tabBorder), left: BorderSide(color: tabBorder), right: BorderSide(color: tabBorder)),
                              ),
                              child: Row(children: [
                                Container(width: 6, height: 6, decoration: BoxDecoration(color: active ? const Color(0xFF2563EB) : Colors.transparent, shape: BoxShape.circle)),
                                const SizedBox(width: 6),
                                Text(t.title, style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: active ? (isDark ? Colors.white : const Color(0xFF0F172A)) : const Color(0xFF64748B))),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () => ref.read(tabWorkspaceProvider.notifier).closeTab(t.id),
                                  borderRadius: BorderRadius.circular(4),
                                  child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.close, size: 14, color: Color(0xFF94A3B8))),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer l\'onglet actif (Ctrl+W)',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => ref.read(tabWorkspaceProvider.notifier).closeActive(),
                ),
              ],
            ),
          ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey(ws.tabs[ws.activeIndex].id),
              child: ws.tabs[ws.activeIndex].builder(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper: ouvrir un module comme onglet de travail.
void openModuleTab(WidgetRef ref,
    {required String id,
    required String title,
    required String route,
    required WidgetBuilder builder}) {
  ref.read(tabWorkspaceProvider.notifier).openTab(
      WorkspaceTab(id: id, title: title, route: route, builder: builder));
}
