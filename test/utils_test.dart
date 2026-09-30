/// Тесты форматирования дат, фильтров задач и ролей в навигации.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/api_client.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/ui/screens/workspace_shell.dart';
import 'package:taskflow/ui/workspace_tab.dart';
import 'package:taskflow/ui/theme.dart';

void main() {
  group('Форматирование дат', () {
    test('сегодня, вчера и завтра', () {
      final now = DateTime.now();
      expect(Format.date(now), 'сегодня');
      expect(Format.date(now.subtract(const Duration(days: 1))), 'вчера');
      expect(Format.date(now.add(const Duration(days: 1))), 'завтра');
    });

    test('пустая дата даёт прочерк', () {
      expect(Format.date(null), '—');
      expect(Format.dateTime(null), '—');
      expect(Format.longDateTime(null), '—');
    });

    test('время в формате ЧЧ:ММ', () {
      final value = DateTime(2026, 3, 15, 9, 5);
      expect(Format.time(value), '09:05');
      expect(Format.time(DateTime(2026, 3, 15, 23, 59)), '23:59');
    });

    test('дата с годом отличается от текущего', () {
      final value = DateTime(2020, 1, 15, 12, 0);
      final text = Format.date(value);
      expect(text, contains('15'));
      expect(text, contains('2020'));
    });

    test('срок задачи с пометкой просрочки', () {
      final past = DateTime.now().subtract(const Duration(days: 3));
      expect(Format.dueLabel(past, overdue: true), contains('просрочено'));
      expect(Format.dueLabel(past), isNot(contains('просрочено')));
    });

    test('без срока пишем «Без срока»', () {
      expect(Format.dueLabel(null), 'Без срока');
    });

    test('длительность голосового', () {
      expect(Format.duration(null), '0:00');
      expect(Format.duration(0), '0:00');
      expect(Format.duration(5), '0:05');
      expect(Format.duration(65), '1:05');
      // Дробные секунды округляются до ближайшей целой.
      expect(Format.duration(125.9), '2:06');
    });

    test('размер файла', () {
      expect(Format.fileSize(512), '512 Б');
      expect(Format.fileSize(2048), '2 КБ');
      expect(Format.fileSize(5 * 1024 * 1024), '5.0 МБ');
    });

    test('относительное время', () {
      expect(Format.ago(null), '');
      expect(Format.ago(DateTime.now()), 'сейчас');
      expect(
        Format.ago(DateTime.now().subtract(const Duration(minutes: 5))),
        '5 мин назад',
      );
      expect(
        Format.ago(DateTime.now().subtract(const Duration(hours: 3))),
        '3 ч назад',
      );
    });
  });

  group('TaskFilter', () {
    test('пустой фильтр не считается активным', () {
      const filter = TaskFilter();
      expect(filter.isEmpty, isTrue);
      expect(filter.activeCount, 0);
    });

    test('каждое условие увеличивает счётчик', () {
      const filter = TaskFilter(
        search: 'диск',
        statuses: [TaskStatus.done],
        priorities: [TaskPriority.urgent],
        overdueOnly: true,
      );
      expect(filter.activeCount, 4);
      expect(filter.isEmpty, isFalse);
    });

    test('копирование сохраняет остальные условия', () {
      const filter = TaskFilter(search: 'диск', overdueOnly: true);
      final copy = filter.copyWith(search: 'принтер');

      expect(copy.search, 'принтер');
      expect(copy.overdueOnly, isTrue);
    });

    test('исполнителя можно сбросить', () {
      const filter = TaskFilter(assigneeId: 'u1');
      final copy = filter.copyWith(clearAssignee: true);
      expect(copy.assigneeId, isNull);
    });
  });

  group('Доступность вкладок по роли', () {
    final manager = AppUser.fromJson({
      'id': 'u1',
      'username': 'head',
      'full_name': 'Глава',
      'permissions': [
        'users.view',
        'users.create',
        'tasks.view',
        'tasks.reports',
        'chat.direct',
      ],
    });

    final staff = AppUser.fromJson({
      'id': 'u2',
      'username': 'staff',
      'full_name': 'Сотрудник',
      'permissions': ['tasks.view', 'chat.direct'],
    });

    test('у сотрудника нет управленческих вкладок', () {
      final tabs = tabsFor(staff);
      expect(tabs, isNot(contains(WorkspaceTab.team)));
      expect(tabs, isNot(contains(WorkspaceTab.reports)));
      expect(tabs, contains(WorkspaceTab.tasks));
      expect(tabs, contains(WorkspaceTab.chats));
      expect(tabs, contains(WorkspaceTab.profile));
    });

    test('у главы отдела есть отдел и отчёты', () {
      final tabs = tabsFor(manager);
      expect(tabs, contains(WorkspaceTab.team));
      expect(tabs, contains(WorkspaceTab.reports));
    });

    test('без данных пользователя показываем базовые вкладки', () {
      final tabs = tabsFor(null);
      expect(tabs.length, 3);
      expect(tabs.first, WorkspaceTab.tasks);
    });

    test('задачи и чаты есть всегда', () {
      for (final user in [staff, manager]) {
        final tabs = tabsFor(user);
        expect(tabs, contains(WorkspaceTab.tasks));
        expect(tabs, contains(WorkspaceTab.chats));
      }
    });
  });

  group('Оформление', () {
    test('цвет статуса задан для всех статусов', () {
      for (final status in TaskStatus.values) {
        expect(AppColors.statusColor(status.wire), isNotNull);
      }
      expect(AppColors.statusColor('done'), AppColors.success);
      expect(AppColors.statusColor('cancelled'), AppColors.textMuted);
    });

    test('цвет приоритета срочного — красный', () {
      expect(AppColors.priorityColor('urgent'), AppColors.danger);
    });

    test('цвет аватара стабилен для сотрудника', () {
      final first = AppColors.avatar('user-123');
      final second = AppColors.avatar('user-123');
      expect(first, second);
    });

    test('цвет аватара разный у разных людей', () {
      expect(
        AppColors.avatar('user-1') == AppColors.avatar('user-2'),
        isFalse,
      );
    });

    test('темы собираются в светлом и тёмном режиме', () {
      final light = AppTheme.light();
      final dark = AppTheme.dark();

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
    });
  });

  group('Метаданные сервера', () {
    test('разбираются из ответа', () {
      final info = ServerInfo.fromJson({
        'name': 'TaskFlow',
        'version': '1.0.0',
        'requires_setup': true,
        'voice_enabled': true,
        'voice_model': 'base',
      });
      expect(info.name, 'TaskFlow');
      expect(info.requiresSetup, isTrue);
      expect(info.voiceEnabled, isTrue);
      expect(info.voiceModel, 'base');
    });

    test('пустой ответ даёт значения по умолчанию', () {
      final info = ServerInfo.fromJson({});
      expect(info.name, 'TaskFlow');
      expect(info.requiresSetup, isFalse);
      expect(info.voiceEnabled, isFalse);
    });
  });
}
