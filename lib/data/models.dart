/// Модели данных TaskFlow. Зеркалят ответы сервера.
library;

import 'dart:convert';

import '../l10n/data_labels.dart';
import '../l10n/error_messages.dart';
import '../l10n/generated/app_localizations.dart';

/// Разбирает дату из строки ISO-8601, которую отдаёт сервер.
DateTime? parseServerDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  final text = value.toString();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}

class Json {
  const Json._();

  static String? string(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static String text(Object? value, [String fallback = '']) =>
      value == null ? fallback : value.toString();

  static int integer(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double number(Object? value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static bool flag(Object? value, [bool fallback = false]) {
    if (value is bool) return value;
    if (value == null) return fallback;
    return value.toString().toLowerCase() == 'true';
  }

  static List<String> strings(Object? value) {
    if (value is! List) return const [];
    return value.map((item) => item.toString()).toList();
  }

  static Map<String, dynamic>? object(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return null;
  }

  static List<Map<String, dynamic>> objects(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Object>()
        .map(object)
        .whereType<Map<String, dynamic>>()
        .toList();
  }
}

/// Общая карточка вложения: фотоотчёт, документ или аудио голосового.
class Attachment {
  const Attachment({
    required this.id,
    required this.kind,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    this.url,
    this.previewUrl,
    this.width,
    this.height,
    this.durationSec,
  });

  final String id;
  final String kind;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final String? url;
  final String? previewUrl;
  final int? width;
  final int? height;
  final double? durationSec;

  bool get isImage => kind == 'image';
  bool get isAudio => kind == 'audio';

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: Json.text(json['id']),
        kind: Json.text(json['kind'], 'other'),
        name: Json.text(json['name']),
        mimeType: Json.text(json['mime_type'], 'application/octet-stream'),
        sizeBytes: Json.integer(json['size_bytes']),
        url: Json.string(json['url']),
        previewUrl: Json.string(json['preview_url']),
        width: json['width'] == null ? null : Json.integer(json['width']),
        height: json['height'] == null ? null : Json.integer(json['height']),
        durationSec: json['duration_sec'] == null
            ? null
            : Json.number(json['duration_sec']),
      );

  /// Размер файла для подписи под вложением.
  ///
  /// Единицы измерения берём из переводов: в английском интерфейсе
  /// подпись должна быть в килобайтах и мегабайтах, а не в кило- и
  /// мегабайтах русской типографики.
  String humanSize(AppLocalizations l10n) {
    if (sizeBytes < 1024) return l10n.sizeBytes(sizeBytes);
    if (sizeBytes < 1024 * 1024) {
      return l10n.sizeKilobytes((sizeBytes / 1024).toStringAsFixed(1));
    }
    return l10n.sizeMegabytes((sizeBytes / (1024 * 1024)).toStringAsFixed(1));
  }
}

/// Роль с набором прав.
class Role {
  const Role({
    required this.id,
    required this.key,
    required this.title,
    this.i18nKey,
    this.permissions = const [],
    this.isSystem = false,
  });

  final String id;
  final String key;
  final String title;

  /// Идентификатор системной роли ('admin', 'head', 'staff').
  ///
  /// Ключ роли в базе русский, поэтому сервер отдаёт отдельное
  /// независимое от языка поле: по нему клиент показывает своё
  /// название. У своих ролей поле пустое.
  final String? i18nKey;

  final List<String> permissions;
  final bool isSystem;

  /// Название роли на языке интерфейса.
  String localizedTitle(AppLocalizations l10n) =>
      DataLabels.roleName(title, i18nKey, l10n);

  factory Role.fromJson(Map<String, dynamic> json) => Role(
        id: Json.text(json['id']),
        key: Json.text(json['key']),
        title: Json.text(json['title']),
        i18nKey: Json.string(json['i18n_key']),
        permissions: Json.strings(json['permissions']),
        isSystem: Json.flag(json['is_system']),
      );
}

/// Краткая карточка сотрудника — для списков, чатов и задач.
class UserBrief {
  const UserBrief({
    required this.id,
    required this.username,
    required this.fullName,
    this.avatarUrl,
    this.isActive = true,
  });

  final String id;
  final String username;
  final String fullName;
  final String? avatarUrl;
  final bool isActive;

  /// Имя для показа: сначала ФИО, при его отсутствии — логин.
  String get displayName => fullName.isNotEmpty ? fullName : username;

  /// Подпись под именем. В полной карточке переопределяется на роль.
  String get subtitle => '@$username';

  /// Инициалы для кружка аватара.
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters;
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }

  factory UserBrief.fromJson(Map<String, dynamic> json) {
    return UserBrief(
      id: Json.text(json['id']),
      username: Json.text(json['username']),
      fullName: Json.text(json['full_name']),
      avatarUrl: Json.string(json['avatar_url']),
      isActive: Json.flag(json['is_active'], true),
    );
  }
}

extension on String {
  String get characters => isEmpty ? '' : this[0];
}

/// Полная карточка сотрудника.
class AppUser extends UserBrief {
  const AppUser({
    required super.id,
    required super.username,
    required super.fullName,
    super.avatarUrl,
    super.isActive,
    this.email,
    this.phone,
    this.roles = const [],
    this.permissions = const [],
    this.isSuperuser = false,
    this.mustChangePassword = false,
    this.lastLoginAt,
    this.createdAt,
  });

  final String? email;
  final String? phone;
  final List<Role> roles;
  final List<String> permissions;
  final bool isSuperuser;
  final bool mustChangePassword;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;

  bool get isManager =>
      permissions.contains('users.create') ||
      permissions.contains('tasks.view_all');

  bool get isAdmin =>
      isSuperuser || permissions.contains('settings.manage_roles');

  /// Есть ли конкретное право. Единая точка проверки прав в интерфейсе.
  bool can(String permission) =>
      isSuperuser || permissions.contains(permission);

  /// Подпись под именем: роль вместо убранной должности.
  ///
  /// Показываем все роли, а не только первую: у сотрудника их может
  /// быть несколько, и одна не описывает его работу.
  String subtitleWith(AppLocalizations l10n) {
    if (roles.isEmpty) return '@$username';
    return roles.map((role) => role.localizedTitle(l10n)).join(', ');
  }

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: Json.text(json['id']),
        username: Json.text(json['username']),
        fullName: Json.text(json['full_name']),
        avatarUrl: Json.string(json['avatar_url']),
        isActive: Json.flag(json['is_active'], true),
        email: Json.string(json['email']),
        phone: Json.string(json['phone']),
        roles: Json.objects(json['roles']).map(Role.fromJson).toList(),
        permissions: Json.strings(json['permissions']),
        isSuperuser: Json.flag(json['is_superuser']),
        mustChangePassword: Json.flag(json['must_change_password']),
        lastLoginAt: parseServerDate(json['last_login_at']),
        createdAt: parseServerDate(json['created_at']),
      );
}

/// Ответ на вход: пара токенов.
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: Json.text(json['access_token']),
        refreshToken: Json.text(json['refresh_token']),
        expiresIn: Json.integer(json['expires_in']),
      );
}

/// Статус задачи.
///
/// Имя `created` вместо `new`: `new` в Dart — зарезервированное слово,
/// поэтому такое имя члена перечисления недопустимо. По сети статус
/// по-прежнему передаётся как `new`.
///
/// Человекочитаемое название не хранится в перечислении: оно зависит
/// от языка интерфейса, поэтому берётся из переводов через [title].
enum TaskStatus {
  created('new'),
  inProgress('in_progress'),
  review('review'),
  done('done'),
  cancelled('cancelled');

  const TaskStatus(this.wire);

  /// Значение, которым статус передаётся по сети.
  final String wire;

  /// Название статуса на языке интерфейса.
  String title(AppLocalizations l10n) => switch (this) {
        TaskStatus.created => l10n.statusNew,
        TaskStatus.inProgress => l10n.statusInProgress,
        TaskStatus.review => l10n.statusReview,
        TaskStatus.done => l10n.statusDone,
        TaskStatus.cancelled => l10n.statusCancelled,
      };

  bool get isOpen => this != TaskStatus.done && this != TaskStatus.cancelled;

  static TaskStatus parse(String? value) => values.firstWhere(
        (item) => item.wire == value,
        orElse: () => TaskStatus.created,
      );
}

/// Приоритет задачи.
enum TaskPriority {
  low('low'),
  normal('normal'),
  high('high'),
  urgent('urgent');

  const TaskPriority(this.wire);

  final String wire;

  String title(AppLocalizations l10n) => switch (this) {
        TaskPriority.low => l10n.priorityLow,
        TaskPriority.normal => l10n.priorityNormal,
        TaskPriority.high => l10n.priorityHigh,
        TaskPriority.urgent => l10n.priorityUrgent,
      };

  int get weight => switch (this) {
        TaskPriority.low => 0,
        TaskPriority.normal => 1,
        TaskPriority.high => 2,
        TaskPriority.urgent => 3,
      };

  static TaskPriority parse(String? value) => values.firstWhere(
        (item) => item.wire == value,
        orElse: () => TaskPriority.normal,
      );
}

/// Метка задачи.
class TaskTag {
  const TaskTag({required this.id, required this.name, this.color});

  final String id;
  final String name;
  final String? color;

  factory TaskTag.fromJson(Map<String, dynamic> json) => TaskTag(
        id: Json.text(json['id']),
        name: Json.text(json['name']),
        color: Json.string(json['color']),
      );
}

/// Задача.
class Task {
  const Task({
    required this.id,
    required this.title,
    this.description,
    this.status = TaskStatus.created,
    this.priority = TaskPriority.normal,
    this.author,
    this.assignee,
    this.dueAt,
    this.completedAt,
    this.estimatedHours,
    this.tags = const [],
    this.isOverdue = false,
    this.commentsCount = 0,
    this.attachmentsCount = 0,
    this.createdAt,
    this.updatedAt,
    this.comments = const [],
    this.history = const [],
    this.attachments = const [],
  });

  final String id;
  final String title;
  final String? description;
  final TaskStatus status;
  final TaskPriority priority;
  final UserBrief? author;
  final UserBrief? assignee;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final double? estimatedHours;
  final List<TaskTag> tags;
  final bool isOverdue;
  final int commentsCount;
  final int attachmentsCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Заполняются только в карточке задачи: список их не возвращает.
  final List<TaskComment> comments;
  final List<TaskHistoryEntry> history;
  final List<Attachment> attachments;

  bool get hasDetails => comments.isNotEmpty || history.isNotEmpty;

  factory Task.fromJson(Map<String, dynamic> json) {
    final author = Json.object(json['author']);
    final assignee = Json.object(json['assignee']);
    return Task(
      id: Json.text(json['id']),
      title: Json.text(json['title']),
      description: Json.string(json['description']),
      status: TaskStatus.parse(Json.string(json['status'])),
      priority: TaskPriority.parse(Json.string(json['priority'])),
      author: author == null ? null : UserBrief.fromJson(author),
      assignee: assignee == null ? null : UserBrief.fromJson(assignee),
      dueAt: parseServerDate(json['due_at']),
      completedAt: parseServerDate(json['completed_at']),
      estimatedHours: json['estimated_hours'] == null
          ? null
          : Json.number(json['estimated_hours']),
      tags: Json.objects(json['tags']).map(TaskTag.fromJson).toList(),
      isOverdue: Json.flag(json['is_overdue']),
      commentsCount: Json.integer(json['comments_count']),
      attachmentsCount: Json.integer(json['attachments_count']),
      createdAt: parseServerDate(json['created_at']),
      updatedAt: parseServerDate(json['updated_at']),
      comments:
          Json.objects(json['comments']).map(TaskComment.fromJson).toList(),
      history:
          Json.objects(json['history']).map(TaskHistoryEntry.fromJson).toList(),
      attachments:
          Json.objects(json['attachments']).map(Attachment.fromJson).toList(),
    );
  }
}

/// Комментарий к задаче, в том числе фотоотчёт.
class TaskComment {
  const TaskComment({
    required this.id,
    required this.taskId,
    this.body,
    this.author,
    this.attachments = const [],
    this.isWorkReport = false,
    this.createdAt,
  });

  final String id;
  final String taskId;
  final String? body;
  final UserBrief? author;
  final List<Attachment> attachments;
  final bool isWorkReport;
  final DateTime? createdAt;

  factory TaskComment.fromJson(Map<String, dynamic> json) {
    final author = Json.object(json['author']);
    return TaskComment(
      id: Json.text(json['id']),
      taskId: Json.text(json['task_id']),
      body: Json.string(json['body']),
      author: author == null ? null : UserBrief.fromJson(author),
      attachments:
          Json.objects(json['attachments']).map(Attachment.fromJson).toList(),
      isWorkReport: Json.flag(json['is_work_report']),
      createdAt: parseServerDate(json['created_at']),
    );
  }
}

/// Запись в журнале изменений задачи.
class TaskHistoryEntry {
  const TaskHistoryEntry({
    required this.id,
    required this.field,
    this.oldValue,
    this.newValue,
    this.user,
    this.createdAt,
  });

  final String id;
  final String field;
  final String? oldValue;
  final String? newValue;
  final UserBrief? user;
  final DateTime? createdAt;

  /// Человекочитаемое название поля: сервер присылает ключ.
  String fieldTitle(AppLocalizations l10n) => switch (field) {
        'title' => l10n.taskFieldTitle,
        'description' => l10n.taskFieldDescription,
        'status' => l10n.taskFieldStatus,
        'priority' => l10n.taskFieldPriority,
        'assignee_id' => l10n.taskFieldAssignee,
        'due_at' => l10n.taskFieldDue,
        'estimated_hours' => l10n.taskFieldEstimate,
        _ => field,
      };

  factory TaskHistoryEntry.fromJson(Map<String, dynamic> json) {
    final user = Json.object(json['user']);
    return TaskHistoryEntry(
      id: Json.text(json['id']),
      field: Json.text(json['field']),
      oldValue: Json.string(json['old_value']),
      newValue: Json.string(json['new_value']),
      user: user == null ? null : UserBrief.fromJson(user),
      createdAt: parseServerDate(json['created_at']),
    );
  }
}

/// Результат распознавания голосового сообщения.
class Transcript {
  const Transcript({
    required this.id,
    required this.status,
    this.text,
    this.language,
    this.modelName,
    this.durationSec,
    this.confidence,
    this.error,
    this.isManual = false,
  });

  final String id;
  final String status;
  final String? text;
  final String? language;
  final String? modelName;
  final double? durationSec;
  final double? confidence;
  final String? error;
  final bool isManual;

  bool get isPending => status == 'pending' || status == 'running';
  bool get isDone => status == 'done';
  bool get hasError => status == 'failed' || status == 'skipped';

  factory Transcript.fromJson(Map<String, dynamic> json) => Transcript(
        id: Json.text(json['id']),
        status: Json.text(json['status'], 'pending'),
        text: Json.string(json['text']),
        language: Json.string(json['language']),
        modelName: Json.string(json['model_name']),
        durationSec: json['duration_sec'] == null
            ? null
            : Json.number(json['duration_sec']),
        confidence:
            json['confidence'] == null ? null : Json.number(json['confidence']),
        error: Json.string(json['error']),
        isManual: Json.flag(json['is_manual']),
      );
}

/// Сообщение чата.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.seq,
    required this.kind,
    required this.status,
    this.body,
    this.sender,
    this.attachment,
    this.transcript,
    this.transcriptText,
    this.voiceDurationSec,
    this.replyToId,
    this.editedAt,
    this.deletedAt,
    this.createdAt,
  });

  final String id;
  final String chatId;
  final int seq;
  final String kind;
  final String status;
  final String? body;
  final UserBrief? sender;
  final Attachment? attachment;
  final Transcript? transcript;
  final String? transcriptText;
  final double? voiceDurationSec;
  final String? replyToId;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final DateTime? createdAt;

  bool get isVoice => kind == 'voice';
  bool get isImage => kind == 'image';
  bool get isFile => kind == 'file';
  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;

  bool get isRead => status == 'read';
  bool get isDelivered => status == 'delivered' || isRead;

  /// Показывать ли статус доставки: у исходящих сообщений.
  bool get showsStatus => status == 'sent' || status == 'delivered';

  /// Текст для предпросмотра в списке чатов.
  String preview(AppLocalizations l10n) {
    if (isDeleted) return l10n.chatMessageDeleted;
    if (isVoice) {
      final recognized = transcriptText ?? transcript?.text;
      if (recognized != null && recognized.isNotEmpty) return '🎤 $recognized';
      if (transcript?.isPending ?? false) return l10n.chatKindVoicePending;
      return l10n.chatKindVoice;
    }
    if (isImage) return l10n.chatKindPhoto;
    if (isFile && (body == null || body!.isEmpty)) return l10n.chatKindFile;
    return body ?? '';
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final sender = Json.object(json['sender']);
    final attachment = Json.object(json['attachment']);
    final transcript = Json.object(json['transcript']);
    return ChatMessage(
      id: Json.text(json['id']),
      chatId: Json.text(json['chat_id']),
      seq: Json.integer(json['seq']),
      kind: Json.text(json['kind'], 'text'),
      status: Json.text(json['status'], 'sent'),
      body: Json.string(json['body']),
      sender: sender == null ? null : UserBrief.fromJson(sender),
      attachment: attachment == null ? null : Attachment.fromJson(attachment),
      transcript: transcript == null ? null : Transcript.fromJson(transcript),
      transcriptText: Json.string(json['transcript_text']),
      voiceDurationSec: json['voice_duration_sec'] == null
          ? null
          : Json.number(json['voice_duration_sec']),
      replyToId: Json.string(json['reply_to_id']),
      editedAt: parseServerDate(json['edited_at']),
      deletedAt: parseServerDate(json['deleted_at']),
      createdAt: parseServerDate(json['created_at']),
    );
  }
}

/// Чат: личный диалог или группа.
class Chat {
  const Chat({
    required this.id,
    required this.kind,
    this.title,
    this.avatarUrl,
    this.members = const [],
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.isAdmin = false,
    this.isMuted = false,
  });

  final String id;
  final String kind;
  final String? title;
  final String? avatarUrl;
  final List<UserBrief> members;
  final ChatMessage? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool isAdmin;
  final bool isMuted;

  bool get isGroup => kind == 'group';

  /// Название для шапки чата: у диалога — имя собеседника.
  String displayTitle(AppLocalizations l10n) {
    if (isGroup) {
      return title?.isNotEmpty == true ? title! : l10n.chatKindGroup;
    }
    return title?.isNotEmpty == true ? title! : l10n.chatKindDirect;
  }

  factory Chat.fromJson(Map<String, dynamic> json) {
    final last = Json.object(json['last_message']);
    return Chat(
      id: Json.text(json['id']),
      kind: Json.text(json['kind'], 'direct'),
      title: Json.string(json['title']),
      avatarUrl: Json.string(json['avatar_url']),
      members: Json.objects(json['members']).map(UserBrief.fromJson).toList(),
      lastMessage: last == null ? null : ChatMessage.fromJson(last),
      lastMessageAt: parseServerDate(json['last_message_at']),
      unreadCount: Json.integer(json['unread_count']),
      isAdmin: Json.flag(json['is_admin']),
      isMuted: Json.flag(json['is_muted']),
    );
  }
}

/// Страница результатов с курсорной пагинацией.
class Paged<T> {
  const Paged({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
    this.total,
  });

  final List<T> items;
  final String? nextCursor;
  final bool hasMore;
  final int? total;

  factory Paged.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) =>
      Paged(
        items: Json.objects(json['items']).map(parse).toList(),
        nextCursor: Json.string(json['next_cursor']),
        hasMore: Json.flag(json['has_more']),
        total: json['total'] == null ? null : Json.integer(json['total']),
      );
}

/// Сводка по задачам для главы отдела.
class TaskSummary {
  const TaskSummary({
    required this.total,
    required this.byStatus,
    required this.byPriority,
    required this.createdThisWeek,
    required this.completedThisWeek,
    required this.overdue,
    required this.unassigned,
    required this.completionRate,
  });

  final int total;
  final Map<String, int> byStatus;
  final Map<String, int> byPriority;
  final int createdThisWeek;
  final int completedThisWeek;
  final int overdue;
  final int unassigned;
  final double completionRate;

  int countFor(TaskStatus status) => byStatus[status.wire] ?? 0;

  factory TaskSummary.fromJson(Map<String, dynamic> json) {
    Map<String, int> toCounts(Object? value) {
      final map = Json.object(value) ?? const {};
      return map.map((key, item) => MapEntry(key, Json.integer(item)));
    }

    return TaskSummary(
      total: Json.integer(json['total']),
      byStatus: toCounts(json['by_status']),
      byPriority: toCounts(json['by_priority']),
      createdThisWeek: Json.integer(json['created_this_week']),
      completedThisWeek: Json.integer(json['completed_this_week']),
      overdue: Json.integer(json['overdue']),
      unassigned: Json.integer(json['unassigned']),
      completionRate: Json.number(json['completion_rate']),
    );
  }
}

/// Строка отчёта по нагрузке сотрудника.
class UserLoad {
  const UserLoad({
    required this.user,
    required this.assigned,
    required this.inProgress,
    required this.completed,
    required this.overdue,
    required this.completionRate,
    this.reportsCount = 0,
  });

  final UserBrief user;
  final int assigned;
  final int inProgress;
  final int completed;
  final int overdue;
  final double completionRate;
  final int reportsCount;

  factory UserLoad.fromJson(Map<String, dynamic> json) {
    final user = Json.object(json['user']);
    return UserLoad(
      user: user == null
          ? const UserBrief(id: '', username: '', fullName: '')
          : UserBrief.fromJson(user),
      assigned: Json.integer(json['assigned']),
      inProgress: Json.integer(json['in_progress']),
      completed: Json.integer(json['completed']),
      overdue: Json.integer(json['overdue']),
      completionRate: Json.number(json['completion_rate']),
      reportsCount: Json.integer(json['reports_count']),
    );
  }
}

/// Сведения о сервере: клиент проверяет адрес перед входом.
class ServerInfo {
  const ServerInfo({
    required this.name,
    required this.version,
    required this.requiresSetup,
    required this.voiceEnabled,
    required this.voiceModel,
  });

  final String name;
  final String version;
  final bool requiresSetup;
  final bool voiceEnabled;
  final String voiceModel;

  factory ServerInfo.fromJson(Map<String, dynamic> json) => ServerInfo(
        name: Json.text(json['name'], 'TaskFlow'),
        version: Json.text(json['version'], '?'),
        requiresSetup: Json.flag(json['requires_setup']),
        voiceEnabled: Json.flag(json['voice_enabled']),
        voiceModel: Json.text(json['voice_model'], '?'),
      );
}

/// Право с названием — для экрана настройки ролей.
class PermissionInfo {
  const PermissionInfo({
    required this.key,
    required this.title,
    required this.group,
    this.description = '',
  });

  final String key;
  final String title;
  final String group;
  final String description;

  factory PermissionInfo.fromJson(Map<String, dynamic> json) => PermissionInfo(
        key: Json.text(json['key']),
        title: Json.text(json['title']),
        group: Json.text(json['group']),
        description: Json.text(json['description']),
      );
}

/// Ответ сервера об ошибке в едином формате.
class ApiErrorInfo {
  const ApiErrorInfo({required this.code, this.message = '', this.details});

  final String code;
  final String message;
  final Object? details;

  factory ApiErrorInfo.fromJson(Map<String, dynamic> json) {
    final error = Json.object(json['error']) ?? json;
    return ApiErrorInfo(
      code: Json.text(error['code'], 'unknown'),
      // Пустая строка вместо русской заглушки: текст подставит
      // перевод по коду ошибки, иначе неизвестный код показался бы
      // сотруднику русским словом в английском интерфейсе.
      message: Json.text(error['message']),
      details: error['details'],
    );
  }

  /// Понятные сообщения для частых ошибок сервера.
  /// Текст для сотрудника на языке интерфейса.
  ///
  /// Перевод по коду ошибки: сервер присылает текст для отладки, а
  /// этот текст — на языке интерфейса. Пустое сообщение означает
  /// «сервер ничего не прислал», и тогда берётся общая формулировка.
  String localized(AppLocalizations l10n) => translateErrorCode(
        code,
        l10n,
        fallback: message.isEmpty ? null : message,
      );

  static ApiErrorInfo parse(Object? body) {
    if (body is String) {
      if (body.isEmpty) {
        return const ApiErrorInfo(
          code: 'empty_response',
          message: '',
        );
      }
      try {
        return ApiErrorInfo.fromJson(
          jsonDecode(body) as Map<String, dynamic>,
        );
      } catch (_) {
        return ApiErrorInfo(code: 'unknown', message: body);
      }
    }
    if (body is Map<String, dynamic>) {
      return ApiErrorInfo.fromJson(body);
    }
    return const ApiErrorInfo(
      code: 'unknown',
      message: '',
    );
  }
}
