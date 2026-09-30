import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Разделы рабочего пространства.
///
/// Перечисление живёт отдельно от оболочки, чтобы экран отчётов мог
/// переключить сотрудника на задачи: иначе получился бы круговой импорт
/// (оболочка открывает отчёты, отчёты — оболочку).
enum WorkspaceTab {
  tasks('Задачи', Icons.checklist_rtl_outlined, Icons.checklist_rtl),
  chats('Чаты', Icons.forum_outlined, Icons.forum),
  team('Отдел', Icons.groups_outlined, Icons.groups),
  reports('Отчёты', Icons.bar_chart_outlined, Icons.bar_chart),
  profile('Профиль', Icons.person_outline, Icons.person);

  const WorkspaceTab(this.title, this.icon, this.activeIcon);

  final String title;
  final IconData icon;
  final IconData activeIcon;
}

/// Активный раздел оболочки.
///
/// Нужен, чтобы экран отчётов мог перевести сотрудника на задачи с
/// готовым фильтром: плитки цифр должны не просто менять фильтр, а
/// показывать сам список.
final workspaceTabProvider = StateProvider<WorkspaceTab>(
  (ref) => WorkspaceTab.tasks,
);
