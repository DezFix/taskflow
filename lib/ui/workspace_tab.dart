import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';

/// Разделы рабочего пространства.
///
/// Перечисление живёт отдельно от оболочки, чтобы экран отчётов мог
/// переключить сотрудника на задачи: иначе получился бы круговой импорт
/// (оболочка открывает отчёты, отчёты — оболочку).
///
/// Название раздела хранится не здесь, а в переводах: иначе пришлось бы
/// держать три языка в коде.
enum WorkspaceTab {
  tasks(Icons.checklist_rtl_outlined, Icons.checklist_rtl),
  chats(Icons.forum_outlined, Icons.forum),
  team(Icons.groups_outlined, Icons.groups),
  reports(Icons.bar_chart_outlined, Icons.bar_chart),
  profile(Icons.person_outline, Icons.person);

  const WorkspaceTab(this.icon, this.activeIcon);

  final IconData icon;
  final IconData activeIcon;

  /// Название вкладки на языке интерфейса.
  String title(AppLocalizations l10n) => switch (this) {
        WorkspaceTab.tasks => l10n.tabTasks,
        WorkspaceTab.chats => l10n.tabChats,
        WorkspaceTab.team => l10n.tabTeam,
        WorkspaceTab.reports => l10n.tabReports,
        WorkspaceTab.profile => l10n.tabProfile,
      };
}

/// Активный раздел оболочки.
///
/// Нужен, чтобы экран отчётов мог перевести сотрудника на задачи с
/// готовым фильтром: плитки цифр должны не просто менять фильтр, а
/// показывать сам список.
final workspaceTabProvider = StateProvider<WorkspaceTab>(
  (ref) => WorkspaceTab.tasks,
);
