/// Главная оболочка: нижняя навигация и рабочее пространство по роли.
///
/// Одна структура на всех, но состав вкладок зависит от прав сотрудника:
/// у главы отдела есть управленческие разделы, у исполнителя — нет.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/controllers.dart';
import '../theme.dart';
import '../widgets.dart';
import '../workspace_tab.dart';
import 'chat_list_screen.dart';
import 'profile_screen.dart';
import 'reports_screen.dart';
import 'task_list_screen.dart';
import 'team_screen.dart';

/// Какие разделы видит сотрудник.
List<WorkspaceTab> tabsFor(AppUser? user) {
  final tabs = <WorkspaceTab>[WorkspaceTab.tasks, WorkspaceTab.chats];

  // Управленческие разделы доступны только тем, кто управляет отделом.
  if (user != null && (user.can('users.view') && user.can('users.create'))) {
    tabs.add(WorkspaceTab.team);
  }
  if (user != null && user.can('tasks.reports')) {
    tabs.add(WorkspaceTab.reports);
  }
  tabs.add(WorkspaceTab.profile);
  return tabs;
}

class WorkspaceShell extends ConsumerStatefulWidget {
  const WorkspaceShell({super.key});

  @override
  ConsumerState<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends ConsumerState<WorkspaceShell> {
  // Активный раздел хранится в провайдере: экраны вроде отчётов
  // переключают сотрудника на задачи по готовому фильтру.
  WorkspaceTab get _tab => ref.watch(workspaceTabProvider);
  final _navigatorKeys = <WorkspaceTab, GlobalKey<NavigatorState>>{};

  @override
  void initState() {
    super.initState();
    // Сотрудник без управленческих прав сразу попадает в «своё» пространство.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openDefaultTab();
      ref.read(chatListProvider.notifier).load();
    });
  }

  void _openDefaultTab() {
    final user = ref.read(currentUserProvider);
    final available = tabsFor(user);
    if (available.contains(_tab)) return;
    ref.read(workspaceTabProvider.notifier).state =
        available.contains(WorkspaceTab.tasks)
            ? WorkspaceTab.tasks
            : available.first;
  }

  GlobalKey<NavigatorState> _keyFor(WorkspaceTab tab) =>
      _navigatorKeys.putIfAbsent(tab, () => GlobalKey<NavigatorState>());

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final unread = ref.watch(unreadProvider);
    final tabs = tabsFor(user);

    // Права могли измениться: подстраиваем активную вкладку.
    if (!tabs.contains(_tab)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openDefaultTab());
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = _keyFor(_tab).currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
        } else if (_tab != tabs.first) {
          ref.read(workspaceTabProvider.notifier).state = tabs.first;
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: tabs.contains(_tab) ? tabs.indexOf(_tab) : 0,
          children: tabs
              .map(
                (tab) => Navigator(
                  key: _keyFor(tab),
                  onGenerateRoute: (settings) =>
                      MaterialPageRoute(builder: (_) => _screenFor(tab)),
                ),
              )
              .toList(),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tabs.contains(_tab) ? tabs.indexOf(_tab) : 0,
          onDestinationSelected: (index) {
            ref.read(workspaceTabProvider.notifier).state = tabs[index];
          },
          destinations: tabs
              .map(
                (tab) => NavigationDestination(
                  icon: _iconFor(tab, unread),
                  selectedIcon: _iconFor(tab, unread, selected: true),
                  label: tab.title,
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _iconFor(WorkspaceTab tab, int unread, {bool selected = false}) {
    if (tab == WorkspaceTab.chats && unread > 0) {
      return Badge.count(
        count: unread,
        child: Icon(selected ? tab.activeIcon : tab.icon),
      );
    }
    return Icon(selected ? tab.activeIcon : tab.icon);
  }

  Widget _screenFor(WorkspaceTab tab) => switch (tab) {
        WorkspaceTab.tasks => const TaskListScreen(),
        WorkspaceTab.chats => const ChatListScreen(),
        WorkspaceTab.team => const TeamScreen(),
        WorkspaceTab.reports => const ReportsScreen(),
        WorkspaceTab.profile => const _ProfileShell(),
      };
}

/// Профиль с шапкой и данными сервера.
class _ProfileShell extends ConsumerWidget {
  const _ProfileShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(realtimeStatusProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Insets.md),
            child: Center(
              child: RealtimeIndicator(
                connected: status?.name == 'connected',
                label: status?.name == 'connected' ? 'На связи' : 'Нет связи',
              ),
            ),
          ),
        ],
      ),
      body: const ProfileScreen(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ref.read(realtimeProvider).reconnect(),
        tooltip: 'Переподключить',
        child: const Icon(Icons.sync),
      ),
    );
  }
}

/// Экран загрузки приложения.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.checklist_rtl,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: Insets.md),
            const Text(
              'TaskFlow',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Insets.lg),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
