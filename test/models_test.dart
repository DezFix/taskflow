/// Тесты моделей данных: разбор ответов сервера и крайние случаи.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/models.dart';

void main() {
  group('Разбор дат', () {
    test('ISO с Z разбирается в местное время', () {
      final value = parseServerDate('2026-03-15T10:30:00Z');
      expect(value, isNotNull);
      expect(value!.toUtc().year, 2026);
      expect(value.toUtc().month, 3);
      expect(value.toUtc().day, 15);
    });

    test('пустое значение даёт null', () {
      expect(parseServerDate(null), isNull);
      expect(parseServerDate(''), isNull);
    });

    test('мусор в дате не роняет разбор', () {
      expect(parseServerDate('не дата'), isNull);
    });
  });

  group('Json', () {
    test('числа и флаги читаются из строк', () {
      expect(Json.integer('42'), 42);
      expect(Json.integer('abc', 7), 7);
      expect(Json.number('1.5'), 1.5);
      expect(Json.flag('true'), isTrue);
      expect(Json.flag('False'), isFalse);
      expect(Json.flag(null, true), isTrue);
    });

    test('списки и объекты приводятся к нужным типам', () {
      expect(Json.strings(['a', 1]), ['a', '1']);
      expect(Json.strings(null), isEmpty);
      expect(
          Json.objects([
            {'id': 1}
          ]).length,
          1);
      expect(Json.objects('не список'), isEmpty);
    });
  });

  group('TaskStatus', () {
    test('значения с сервера распознаются', () {
      expect(TaskStatus.parse('new'), TaskStatus.created);
      expect(TaskStatus.parse('in_progress'), TaskStatus.inProgress);
      expect(TaskStatus.parse('done'), TaskStatus.done);
    });

    test('неизвестное значение даёт «Новая», а не исключение', () {
      expect(TaskStatus.parse('что-то'), TaskStatus.created);
      expect(TaskStatus.parse(null), TaskStatus.created);
    });

    test('открыты только незавершённые', () {
      expect(TaskStatus.created.isOpen, isTrue);
      expect(TaskStatus.inProgress.isOpen, isTrue);
      expect(TaskStatus.review.isOpen, isTrue);
      expect(TaskStatus.done.isOpen, isFalse);
      expect(TaskStatus.cancelled.isOpen, isFalse);
    });

    test('по сети передаётся ожидаемое значение', () {
      expect(TaskStatus.created.wire, 'new');
      expect(TaskStatus.inProgress.wire, 'in_progress');
    });
  });

  group('TaskPriority', () {
    test('вес растёт вместе с важностью', () {
      expect(TaskPriority.low.weight, lessThan(TaskPriority.normal.weight));
      expect(TaskPriority.normal.weight, lessThan(TaskPriority.high.weight));
      expect(TaskPriority.high.weight, lessThan(TaskPriority.urgent.weight));
    });

    test('разбор и заголовки', () {
      expect(TaskPriority.parse('urgent'), TaskPriority.urgent);
      expect(TaskPriority.parse('неизвестно'), TaskPriority.normal);
      expect(TaskPriority.urgent.title, 'Срочный');
    });
  });

  group('AppUser', () {
    final json = <String, dynamic>{
      'id': 'u1',
      'username': 'ivan',
      'full_name': 'Иван Иванов',
      'email': 'ivan@example.com',
      'job_title': 'Инженер',
      'is_active': true,
      'permissions': ['tasks.view', 'tasks.create', 'users.create'],
      'roles': [
        {
          'id': 'r1',
          'key': 'Сотрудник',
          'title': 'Сотрудник',
          'permissions': ['tasks.view']
        },
      ],
      'position': {'id': 'p1', 'title': 'Системный инженер'},
    };

    test('права читаются и проверяются', () {
      final user = AppUser.fromJson(json);
      expect(user.can('tasks.view'), isTrue);
      expect(user.can('users.delete'), isFalse);
      expect(user.permissions.length, 3);
    });

    test('управленец определяется по праву создания сотрудников', () {
      final manager = AppUser.fromJson({
        ...json,
        'permissions': ['users.create'],
      });
      expect(manager.isManager, isTrue);
    });

    test('суперпользователь имеет все права', () {
      final admin = AppUser.fromJson({...json, 'is_superuser': true});
      expect(admin.can('что угодно'), isTrue);
      expect(admin.isAdmin, isTrue);
    });

    test('инициалы для аватара', () {
      expect(AppUser.fromJson(json).initials, 'ИИ');
      expect(
        const UserBrief(id: 'x', username: 'a', fullName: 'Петров').initials,
        'П',
      );
    });

    test('подпись показывает должность, иначе логин', () {
      final withPosition = AppUser.fromJson(json);
      expect(withPosition.subtitle, 'Системный инженер');

      final without = AppUser.fromJson({
        ...json,
        'position': null,
        'job_title': null,
      });
      expect(without.subtitle, '@ivan');
    });
  });

  group('Task', () {
    final json = <String, dynamic>{
      'id': 't1',
      'title': 'Заменить диск',
      'status': 'in_progress',
      'priority': 'urgent',
      'is_overdue': true,
      'comments_count': 3,
      'attachments_count': 2,
      'author': {'id': 'u1', 'username': 'boss', 'full_name': 'Начальник'},
      'assignee': {'id': 'u2', 'username': 'petr', 'full_name': 'Пётр Петров'},
      'tags': [
        {'id': 'tag1', 'name': 'Оборудование'},
      ],
      'due_at': '2026-01-01T12:00:00Z',
      'created_at': '2026-01-01T10:00:00Z',
    };

    test('основные поля разбираются', () {
      final task = Task.fromJson(json);
      expect(task.title, 'Заменить диск');
      expect(task.status, TaskStatus.inProgress);
      expect(task.priority, TaskPriority.urgent);
      expect(task.isOverdue, isTrue);
      expect(task.commentsCount, 3);
      expect(task.attachmentsCount, 2);
      expect(task.tags.single.name, 'Оборудование');
      expect(task.assignee?.displayName, 'Пётр Петров');
    });

    test('минимальный ответ не вызывает ошибок', () {
      final task = Task.fromJson({'id': 't2', 'title': 'Простая'});
      expect(task.status, TaskStatus.created);
      expect(task.priority, TaskPriority.normal);
      expect(task.tags, isEmpty);
      expect(task.author, isNull);
      expect(task.isOverdue, isFalse);
    });
  });

  group('TaskHistoryEntry', () {
    test('поле статуса переводится на понятный язык', () {
      final entry = TaskHistoryEntry.fromJson({
        'id': 'h1',
        'field': 'status',
        'old_value': 'Новая',
        'new_value': 'В работе',
      });
      expect(entry.fieldTitle, 'Статус');
      expect(entry.newValue, 'В работе');
    });

    test('неизвестное поле показывается как есть', () {
      final entry = TaskHistoryEntry.fromJson({'id': 'h2', 'field': 'что_то'});
      expect(entry.fieldTitle, 'что_то');
    });
  });

  group('ChatMessage', () {
    test('текстовое сообщение', () {
      final message = ChatMessage.fromJson({
        'id': 'm1',
        'chat_id': 'c1',
        'seq': 5,
        'kind': 'text',
        'body': 'Привет',
        'status': 'read',
        'sender': {'id': 'u1', 'username': 'ivan', 'full_name': 'Иван'},
      });
      expect(message.isVoice, isFalse);
      expect(message.isRead, isTrue);
      expect(message.preview, 'Привет');
    });

    test('голосовое с готовой расшифровкой', () {
      final message = ChatMessage.fromJson({
        'id': 'm2',
        'chat_id': 'c1',
        'seq': 6,
        'kind': 'voice',
        'status': 'sent',
        'transcript_text': 'Почини принтер',
        'voice_duration_sec': 4.5,
      });
      expect(message.isVoice, isTrue);
      expect(message.preview, contains('Почини принтер'));
    });

    test('голосовое в процессе распознавания', () {
      final message = ChatMessage.fromJson({
        'id': 'm3',
        'chat_id': 'c1',
        'seq': 7,
        'kind': 'voice',
        'status': 'sent',
        'transcript': {'id': 'tr1', 'status': 'running'},
      });
      expect(message.preview, contains('Распознаём'));
    });

    test('удалённое сообщение помечается', () {
      final message = ChatMessage.fromJson({
        'id': 'm4',
        'chat_id': 'c1',
        'seq': 8,
        'kind': 'text',
        'status': 'sent',
        'deleted_at': '2026-01-01T10:00:00Z',
      });
      expect(message.isDeleted, isTrue);
      expect(message.preview, 'Сообщение удалено');
    });

    test('отправленное сообщение показывает статус доставки', () {
      final sent = ChatMessage.fromJson({
        'id': 'm5',
        'chat_id': 'c1',
        'seq': 9,
        'kind': 'text',
        'body': 'x',
        'status': 'sent',
      });
      final delivered = ChatMessage.fromJson({
        'id': 'm6',
        'chat_id': 'c1',
        'seq': 10,
        'kind': 'text',
        'body': 'x',
        'status': 'delivered',
      });
      expect(sent.showsStatus, isTrue);
      expect(delivered.showsStatus, isTrue);
      expect(delivered.isDelivered, isTrue);
    });
  });

  group('Transcript', () {
    test('статусы распознавания', () {
      expect(
        const Transcript(id: 't', status: 'pending').isPending,
        isTrue,
      );
      expect(
        const Transcript(id: 't', status: 'running').isPending,
        isTrue,
      );
      expect(const Transcript(id: 't', status: 'done').isDone, isTrue);
      expect(const Transcript(id: 't', status: 'failed').hasError, isTrue);
      expect(const Transcript(id: 't', status: 'skipped').hasError, isTrue);
    });
  });

  group('Chat', () {
    test('у группы есть название, у диалога — имя собеседника', () {
      final group = Chat.fromJson({
        'id': 'c1',
        'kind': 'group',
        'title': 'Отдел ИТ',
      });
      final direct = Chat.fromJson({
        'id': 'c2',
        'kind': 'direct',
        'title': 'Пётр Петров',
      });
      expect(group.isGroup, isTrue);
      expect(group.displayTitle, 'Отдел ИТ');
      expect(direct.isGroup, isFalse);
      expect(direct.displayTitle, 'Пётр Петров');
    });

    test('без названия показывается заглушка', () {
      final chat = Chat.fromJson({'id': 'c3', 'kind': 'direct'});
      expect(chat.displayTitle, 'Диалог');
    });
  });

  group('Paged', () {
    test('курсорная страница разбирается', () {
      final page = Paged.fromJson(
        {
          'items': [
            {'id': 't1', 'title': 'Первая'},
            {'id': 't2', 'title': 'Вторая'},
          ],
          'next_cursor': 'abc',
          'has_more': true,
          'total': 10,
        },
        Task.fromJson,
      );
      expect(page.items.length, 2);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, 'abc');
      expect(page.total, 10);
    });

    test('пустая страница не ломает разбор', () {
      final page = Paged.fromJson({'items': []}, Task.fromJson);
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
    });
  });

  group('ApiErrorInfo', () {
    test('понятные тексты для частых ошибок', () {
      expect(
        ApiErrorInfo.parse({
          'error': {'code': 'invalid_credentials'}
        }).friendly,
        'Неверный логин или пароль',
      );
      expect(
        ApiErrorInfo.parse({
          'error': {'code': 'network_unreachable'}
        }).friendly,
        'Сервер недоступен. Проверьте адрес и подключение',
      );
      expect(
        ApiErrorInfo.parse({
          'error': {'code': 'account_disabled'}
        }).friendly,
        contains('отключена'),
      );
    });

    test('текст ошибки сервера пробрасывается как есть', () {
      final info = ApiErrorInfo.parse({
        'error': {'code': 'file_too_large', 'message': 'Файл больше 25 МБ'},
      });
      expect(info.friendly, 'Файл больше 25 МБ');
    });

    test('мусорный ответ не роняет разбор', () {
      expect(ApiErrorInfo.parse('не json').message, isNotEmpty);
      expect(ApiErrorInfo.parse(null).code, 'unknown');
    });
  });

  group('TaskSummary', () {
    test('сводка считает значения по статусам', () {
      final summary = TaskSummary.fromJson({
        'total': 5,
        'by_status': {'new': 2, 'done': 3},
        'by_priority': {'urgent': 1},
        'created_this_week': 2,
        'completed_this_week': 1,
        'overdue': 1,
        'unassigned': 0,
        'completion_rate': 100.0,
      });
      expect(summary.countFor(TaskStatus.created), 2);
      expect(summary.countFor(TaskStatus.done), 3);
      expect(summary.countFor(TaskStatus.cancelled), 0);
      expect(summary.completionRate, 100.0);
    });
  });

  group('Attachment', () {
    test('размер файла в человекочитаемом виде', () {
      expect(
          const Attachment(
            id: 'a',
            kind: 'image',
            name: 'f',
            mimeType: 'image/png',
            sizeBytes: 512,
          ).humanSize,
          '512 Б');

      expect(
          const Attachment(
            id: 'a',
            kind: 'image',
            name: 'f',
            mimeType: 'image/png',
            sizeBytes: 2048,
          ).humanSize,
          '2.0 КБ');
    });

    test('тип определяется по полю kind', () {
      final image = Attachment.fromJson({
        'id': 'a1',
        'kind': 'image',
        'name': 'p.png',
        'mime_type': 'image/png',
        'size_bytes': 10,
      });
      expect(image.isImage, isTrue);
      expect(image.isAudio, isFalse);
    });
  });
}
