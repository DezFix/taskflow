/// Репозитории: обращения к API, которые вызывают экраны.
library;

import 'dart:typed_data';

import 'api_client.dart';
import 'models.dart';

/// Аутентификация: проверка сервера, вход, выход, профиль.
class AuthRepository {
  AuthRepository(this.client);

  final ApiClient client;

  /// Проверяет, что по указанному адресу отвечает TaskFlow.
  ///
  /// Бросает [ApiException], если адрес не подходит: приложение показывает
  /// сотруднику понятную причину, а не пустой экран.
  Future<ServerInfo> checkServer(String url) async {
    // /meta/info отдаёт один объект, а не массив: getList здесь
    // всегда падал бы и подключиться к серверу было бы невозможно.
    final result = await client.get('/api/v1/meta/info');
    if (result.isEmpty) {
      throw ApiException(
        const ApiErrorInfo(
          code: 'unknown',
          message: 'Сервер не найден или не отвечает',
        ),
      );
    }
    return ServerInfo.fromJson(result.cast<String, dynamic>());
  }

  Future<({AppUser user, AuthTokens tokens})> login({
    required String identifier,
    required String password,
    String? deviceName,
  }) async {
    final data = await client.postPublic(
      '/api/v1/auth/login',
      body: {
        'identifier': identifier.trim(),
        'password': password,
        if (deviceName != null) 'device_name': deviceName,
      },
    );
    final tokens = AuthTokens.fromJson(data);
    client.tokens.accessToken = tokens.accessToken;
    client.tokens.refreshToken = tokens.refreshToken;

    final me = await client.get('/api/v1/auth/me');
    return (user: AppUser.fromJson(me), tokens: tokens);
  }

  /// Первоначальная настройка сервера: создаёт администратора.
  Future<({AppUser user, AuthTokens tokens})> setup({
    required String username,
    required String password,
    required String fullName,
    String? organizationName,
  }) async {
    final data = await client.postPublic(
      '/api/v1/auth/setup',
      body: {
        'username': username.trim(),
        'password': password,
        'full_name': fullName.trim(),
        if (organizationName != null && organizationName.isNotEmpty)
          'organization_name': organizationName.trim(),
      },
    );
    final tokens = AuthTokens.fromJson(data);
    client.tokens.accessToken = tokens.accessToken;
    client.tokens.refreshToken = tokens.refreshToken;

    final me = await client.get('/api/v1/auth/me');
    return (user: AppUser.fromJson(me), tokens: tokens);
  }

  Future<AppUser> me() async {
    final data = await client.get('/api/v1/auth/me');
    return AppUser.fromJson(data);
  }

  Future<AppUser> updateProfile(Map<String, dynamic> changes) async {
    final data = await client.patch('/api/v1/auth/me', body: changes);
    return AppUser.fromJson(data);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    bool allDevices = false,
  }) async {
    await client.post(
      allDevices
          ? '/api/v1/auth/change-password-all'
          : '/api/v1/auth/change-password',
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
  }

  Future<void> logout() async {
    final refresh = client.tokens.refreshToken;
    if (refresh != null && refresh.isNotEmpty) {
      try {
        await client.postPublic(
          '/api/v1/auth/logout',
          body: {'refresh_token': refresh},
        );
      } catch (_) {
        // Выход не должен падать из-за сети: сессию чистим локально.
      }
    }
  }
}

/// Сотрудники, должности и роли.
class DirectoryRepository {
  DirectoryRepository(this.client);

  final ApiClient client;

  /// Сотрудники отдела. Сервер отдаёт полные карточки вместе с ролями.
  Future<List<AppUser>> users({
    String search = '',
    bool? isActive,
    String? positionId,
  }) async {
    final data = await client.getList(
      '/api/v1/users',
      query: {
        'search': search.isEmpty ? null : search,
        'is_active': isActive,
        'position_id': positionId,
      },
    );
    return data
        .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Полная карточка сотрудника с ролями и правами.
  Future<AppUser> user(String id) async {
    final data = await client.get('/api/v1/users/$id');
    return AppUser.fromJson(data);
  }

  Future<({AppUser user, String? temporaryPassword})> createUser({
    required String username,
    required String fullName,
    required List<String> roleIds,
    String? email,
    String? phone,
    String? jobTitle,
    String? positionId,
  }) async {
    final data = await client.post(
      '/api/v1/users',
      body: {
        'username': username.trim(),
        'full_name': fullName.trim(),
        'role_ids': roleIds,
        if (email != null && email.isNotEmpty) 'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (jobTitle != null && jobTitle.isNotEmpty) 'job_title': jobTitle,
        if (positionId != null) 'position_id': positionId,
      },
    );
    return (
      user: AppUser.fromJson(data),
      temporaryPassword: Json.string(data['temporary_password']),
    );
  }

  /// Обновляет сотрудника.
  ///
  /// [clearPosition] нужен, чтобы снять должность: простое отсутствие
  /// значения в [positionId] означало бы «не трогать», и снять
  /// должность было бы невозможно.
  Future<AppUser> updateUser(
    String id, {
    String? fullName,
    String? email,
    String? phone,
    String? jobTitle,
    String? positionId,
    bool clearPosition = false,
    List<String>? roleIds,
    bool? isActive,
  }) async {
    final data = await client.patch(
      '/api/v1/users/$id',
      body: {
        if (fullName != null) 'full_name': fullName,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (jobTitle != null) 'job_title': jobTitle,
        if (clearPosition)
          'position_id': null
        else if (positionId != null)
          'position_id': positionId,
        if (roleIds != null) 'role_ids': roleIds,
        if (isActive != null) 'is_active': isActive,
      },
    );
    return AppUser.fromJson(data);
  }

  Future<String> resetPassword(
    String id, {
    String? newPassword,
    bool mustChange = true,
  }) async {
    final data = await client.post(
      '/api/v1/users/$id/reset-password',
      body: {
        if (newPassword != null) 'new_password': newPassword,
        'must_change_password': mustChange,
      },
    );
    return Json.string(data['temporary_password']) ?? newPassword ?? '';
  }

  Future<AppUser> deactivateUser(String id) async {
    final data = await client.post('/api/v1/users/$id/deactivate');
    return AppUser.fromJson(data);
  }

  Future<AppUser> activateUser(String id) async {
    final data = await client.post('/api/v1/users/$id/activate');
    return AppUser.fromJson(data);
  }

  // --- Должности ---

  Future<List<Position>> positions() async {
    final data = await client.getList('/api/v1/positions');
    return data
        .map((e) => Position.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Position> createPosition(String title, {String? description}) async {
    final data = await client.post(
      '/api/v1/positions',
      body: {
        'title': title.trim(),
        if (description != null && description.isNotEmpty)
          'description': description,
      },
    );
    return Position.fromJson(data);
  }

  Future<void> deletePosition(String id) async {
    await client.delete('/api/v1/positions/$id');
  }

  // --- Роли ---

  Future<List<Role>> roles() async {
    final data = await client.getList('/api/v1/roles');
    return data.map((e) => Role.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Role> createRole({
    required String title,
    required List<String> permissions,
    String? description,
  }) async {
    final data = await client.post(
      '/api/v1/roles',
      body: {
        'title': title.trim(),
        'permissions': permissions,
        if (description != null && description.isNotEmpty)
          'description': description,
      },
    );
    return Role.fromJson(data);
  }

  Future<Role> updateRole(
    String id, {
    String? title,
    List<String>? permissions,
    String? description,
  }) async {
    final data = await client.patch(
      '/api/v1/roles/$id',
      body: {
        if (title != null) 'title': title,
        if (permissions != null) 'permissions': permissions,
        if (description != null) 'description': description,
      },
    );
    return Role.fromJson(data);
  }

  Future<void> deleteRole(String id) async {
    await client.delete('/api/v1/roles/$id');
  }

  Future<List<PermissionInfo>> permissions() async {
    final data = await client.getList('/api/v1/meta/permissions');
    return data
        .map((e) => PermissionInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Задачи, комментарии и файлы.
class TasksRepository {
  TasksRepository(this.client);

  final ApiClient client;

  Future<Paged<Task>> list({
    TaskFilter filter = const TaskFilter(),
    int limit = 50,
    String? cursor,
  }) async {
    final data = await client.get(
      '/api/v1/tasks',
      query: {
        'limit': limit,
        'cursor': cursor,
        'search': filter.search.isEmpty ? null : filter.search,
        'status': filter.statuses.isEmpty
            ? null
            : filter.statuses.map((s) => s.wire).toList(),
        'priority': filter.priorities.isEmpty
            ? null
            : filter.priorities.map((p) => p.wire).toList(),
        'assignee_id': filter.assigneeId,
        'overdue': filter.overdueOnly ? 'true' : null,
        'is_archived': filter.showArchived ? 'true' : 'false',
      },
    );
    return ApiParsers.tasks(data);
  }

  Future<Task> get(String id) async {
    final data = await client.get('/api/v1/tasks/$id');
    return ApiParsers.task(data);
  }

  Future<Task> create({
    required String title,
    String? description,
    String? assigneeId,
    TaskStatus status = TaskStatus.created,
    TaskPriority priority = TaskPriority.normal,
    DateTime? dueAt,
    List<String> tags = const [],
  }) async {
    final data = await client.post(
      '/api/v1/tasks',
      body: {
        'title': title.trim(),
        if (description != null && description.isNotEmpty)
          'description': description,
        if (assigneeId != null) 'assignee_id': assigneeId,
        'status': status.wire,
        'priority': priority.wire,
        if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
        if (tags.isNotEmpty) 'tags': tags,
      },
    );
    return ApiParsers.task(data);
  }

  Future<Task> update(
    String id, {
    String? title,
    String? description,
    TaskPriority? priority,
    DateTime? dueAt,
    List<String>? tags,
  }) async {
    final data = await client.patch(
      '/api/v1/tasks/$id',
      body: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (priority != null) 'priority': priority.wire,
        if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
        if (tags != null) 'tags': tags,
      },
    );
    return ApiParsers.task(data);
  }

  Future<Task> changeStatus(
    String id,
    TaskStatus status, {
    String? comment,
  }) async {
    final data = await client.post(
      '/api/v1/tasks/$id/status',
      body: {
        'status': status.wire,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      },
    );
    return ApiParsers.task(data);
  }

  Future<Task> assign(
    String id, {
    String? assigneeId,
    DateTime? dueAt,
    String? comment,
  }) async {
    final data = await client.post(
      '/api/v1/tasks/$id/assign',
      body: {
        'assignee_id': assigneeId,
        if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      },
    );
    return ApiParsers.task(data);
  }

  Future<void> delete(String id) async {
    await client.delete('/api/v1/tasks/$id');
  }

  Future<TaskComment> addComment(
    String taskId, {
    String? body,
    List<String> attachmentIds = const [],
    bool isWorkReport = false,
  }) async {
    final data = await client.post(
      '/api/v1/tasks/$taskId/comments',
      body: {
        if (body != null && body.isNotEmpty) 'body': body,
        'attachment_ids': attachmentIds,
        'is_work_report': isWorkReport,
      },
    );
    return TaskComment.fromJson(data);
  }

  Future<List<TaskHistoryEntry>> history(String taskId) async {
    final data = await client.getList('/api/v1/tasks/$taskId/history');
    return data
        .map((e) => TaskHistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Attachment> upload({
    required UploadFile file,
    String? taskId,
  }) async {
    final data = await client.upload(
      '/api/v1/files',
      file: file,
      fields: {if (taskId != null) 'task_id': taskId},
    );
    return Attachment.fromJson(data);
  }

  Future<List<TaskTag>> tags() async {
    final data = await client.getList('/api/v1/tasks/tags/list');
    return data
        .map((e) => TaskTag.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Чат: диалоги, группы, сообщения, голосовые.
class ChatRepository {
  ChatRepository(this.client);

  final ApiClient client;

  Future<List<Chat>> chats() async {
    final data = await client.getList('/api/v1/chats');
    return ApiParsers.chatList(data);
  }

  Future<int> unreadTotal() async {
    final data = await client.get('/api/v1/chats/unread/total');
    return Json.integer(data['unread']);
  }

  Future<Chat> openDirect(String userId) async {
    final data = await client.post(
      '/api/v1/chats/direct',
      body: {'user_id': userId},
    );
    return Chat.fromJson(data);
  }

  Future<Chat> createGroup({
    required String title,
    required List<String> memberIds,
  }) async {
    final data = await client.post(
      '/api/v1/chats/groups',
      body: {'title': title.trim(), 'member_ids': memberIds},
    );
    return Chat.fromJson(data);
  }

  Future<Chat> chat(String chatId) async {
    final data = await client.get('/api/v1/chats/$chatId');
    return Chat.fromJson(data);
  }

  Future<Paged<ChatMessage>> messages(
    String chatId, {
    int limit = 50,
    String? beforeSeq,
  }) async {
    final data = await client.get(
      '/api/v1/chats/$chatId/messages',
      query: {'limit': limit, 'before_seq': beforeSeq},
    );
    return ApiParsers.messages(data);
  }

  Future<ChatMessage> sendText(
    String chatId, {
    required String body,
    String? replyToId,
  }) async {
    final data = await client.post(
      '/api/v1/chats/$chatId/messages',
      body: {'body': body, if (replyToId != null) 'reply_to_id': replyToId},
    );
    return ChatMessage.fromJson(data);
  }

  Future<ChatMessage> sendFile(
    String chatId, {
    required UploadFile file,
    String? body,
  }) async {
    final data = await client.upload(
      '/api/v1/chats/$chatId/files',
      file: file,
      fields: {if (body != null && body.isNotEmpty) 'body': body},
    );
    return ChatMessage.fromJson(data);
  }

  Future<ChatMessage> sendVoice(
    String chatId, {
    required UploadFile file,
    double? durationSec,
  }) async {
    final data = await client.upload(
      '/api/v1/chats/$chatId/voice',
      file: file,
      fields: {if (durationSec != null) 'duration_sec': '$durationSec'},
    );
    return ChatMessage.fromJson(data);
  }

  Future<void> markRead(String chatId, int upToSeq) async {
    await client.post(
      '/api/v1/chats/$chatId/read',
      body: {'seq': upToSeq},
    );
  }

  Future<ChatMessage> editMessage(String messageId, String body) async {
    final data = await client.patch(
      '/api/v1/chats/messages/$messageId',
      body: {'body': body},
    );
    return ChatMessage.fromJson(data);
  }

  Future<void> deleteMessage(String messageId) async {
    await client.delete('/api/v1/chats/messages/$messageId');
  }

  /// Исправляет расшифровку вручную, если модель ошиблась.
  Future<Transcript> fixTranscript(String messageId, String text) async {
    final data = await client.post(
      '/api/v1/chats/messages/$messageId/transcript',
      body: {'body': text},
    );
    return Transcript.fromJson(data);
  }

  Future<Map<String, dynamic>> voiceCapabilities() =>
      client.get('/api/v1/chats/voice/capabilities');
}

/// Отчёты и администрирование.
class ReportsRepository {
  ReportsRepository(this.client);

  final ApiClient client;

  Future<TaskSummary> taskSummary() async {
    final data = await client.get('/api/v1/tasks/reports/summary');
    return TaskSummary.fromJson(data);
  }

  Future<List<UserLoad>> userLoad() async {
    final data = await client.get('/api/v1/tasks/reports/user-load');
    return (data['rows'] as List<dynamic>? ?? const [])
        .map((e) => UserLoad.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> myStats() =>
      client.get('/api/v1/tasks/stats/my');

  /// Записи журнала. Сервер отдаёт объект с пагинацией, а не массив.
  Future<List<Map<String, dynamic>>> auditLog({int limit = 100}) async {
    final data = await client.get(
      '/api/v1/admin/audit',
      query: {'limit': limit},
    );
    return Json.objects(data['items']);
  }

  /// Адрес CSV-выгрузки: файл открывается браузером, а не грузится в память.
  /// Скачивает CSV-выгрузку задач.
  ///
  /// Отдавать сотруднику ссылку нельзя: файл закрыт, браузер откроет
  /// его без заголовка с токеном и получит 401. Поэтому байты забираем
  /// сами — заодно запрос переживёт протухший токен.
  Future<Uint8List> exportTasksCsv({
    Map<String, dynamic> query = const {},
  }) async {
    return client.getBytes('/api/v1/admin/reports/tasks.csv', query: query);
  }

  Future<Map<String, dynamic>> voiceSettings() =>
      client.get('/api/v1/voice/settings');

  Future<Map<String, dynamic>> updateVoiceSettings(
          Map<String, dynamic> changes) =>
      client.put('/api/v1/voice/settings', body: changes);

  /// Просит сервер заранее скачать и прогреть модель распознавания.
  ///
  /// Отдельная кнопка, а не пустая запись настроек: warmup реально
  /// скачивает веса в фоне, иначе первый голосовой сотрудника ждал бы
  /// несколько минут молча.
  Future<void> warmUpVoiceModel() async {
    await client.post('/api/v1/voice/warmup');
  }

  /// Статус движка распознавания и очереди.
  Future<Map<String, dynamic>> voiceStatus() async {
    final data = await client.get('/api/v1/voice/status');
    return data;
  }

  Future<Map<String, dynamic>> systemInfo() =>
      client.get('/api/v1/admin/system/info');

  Future<Map<String, dynamic>> createBackup() =>
      client.post('/api/v1/admin/backup');
}
