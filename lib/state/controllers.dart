/// Контроллеры экранов: задачи, чат, сотрудники, отчёты.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/repositories.dart';
import 'app_state.dart';

/// Состояние списка задач с фильтрами и пагинацией.
class TaskListState {
  const TaskListState({
    this.tasks = const [],
    this.filter = const TaskFilter(),
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.nextCursor,
    this.hasMore = false,
    this.total,
  });

  final List<Task> tasks;
  final TaskFilter filter;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final String? nextCursor;
  final bool hasMore;
  final int? total;

  bool get isEmpty => tasks.isEmpty && !isLoading && error == null;

  TaskListState copyWith({
    List<Task>? tasks,
    TaskFilter? filter,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _sentinel,
    String? nextCursor,
    bool clearCursor = false,
    bool? hasMore,
    int? total,
  }) =>
      TaskListState(
        tasks: tasks ?? this.tasks,
        filter: filter ?? this.filter,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        error: identical(error, _sentinel) ? this.error : error as String?,
        nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
        hasMore: hasMore ?? this.hasMore,
        total: total ?? this.total,
      );
}

const Object _sentinel = Object();

class TaskListNotifier extends StateNotifier<TaskListState> {
  TaskListNotifier(this._ref) : super(const TaskListState()) {
    _subscribe();
  }

  final Ref _ref;
  StreamSubscription<dynamic>? _subscription;

  TasksRepository get _repo => _ref.read(tasksRepositoryProvider);

  /// Текущий фильтр: наружу отдаём через метод, а не через поле состояния.
  TaskFilter get filter => state.filter;

  /// Загружает первую страницу с учётом фильтра.
  Future<void> load({TaskFilter? filter, bool showSpinner = true}) async {
    final effective = filter ?? state.filter;
    state = state.copyWith(
      filter: effective,
      isLoading: showSpinner,
      error: null,
      clearCursor: true,
    );
    try {
      final page = await _repo.list(filter: effective);
      state = state.copyWith(
        tasks: page.items,
        isLoading: false,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        total: page.total,
        error: null,
      );
    } on ApiException catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: error.message,
        tasks: const [],
      );
    }
  }

  Future<void> refresh() => load(showSpinner: false);

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.isLoading) return;
    final cursor = state.nextCursor;
    if (cursor == null) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repo.list(filter: state.filter, cursor: cursor);
      // Задачи могли прийти извне: удаляем дубли по идентификатору.
      final known = state.tasks.map((t) => t.id).toSet();
      final merged = [
        ...state.tasks,
        ...page.items.where((t) => !known.contains(t.id)),
      ];
      state = state.copyWith(
        tasks: merged,
        isLoadingMore: false,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );
    } on ApiException {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  void setFilter(TaskFilter filter) {
    load(filter: filter);
  }

  void clearFilter() => setFilter(const TaskFilter());

  /// Создание задачи: добавляем в начало списка без перезагрузки.
  Future<Task?> create({
    required String title,
    String? description,
    String? assigneeId,
    TaskPriority priority = TaskPriority.normal,
    DateTime? dueAt,
  }) async {
    try {
      final task = await _repo.create(
        title: title,
        description: description,
        assigneeId: assigneeId,
        priority: priority,
        dueAt: dueAt,
      );
      if (state.filter.isEmpty) {
        state = state.copyWith(
          tasks: [task, ...state.tasks],
          total: (state.total ?? state.tasks.length) + 1,
        );
      } else {
        // С новым фильтр��м список может измениться — перезагружаем.
        unawaited(refresh());
      }
      return task;
    } on ApiException catch (error) {
      _ref.read(appErrorBusProvider).show(error.message);
      return null;
    }
  }

  /// Смена статуса: обновляем задачу на месте, чтобы интерфейс не мигал.
  Future<bool> changeStatus(String taskId, TaskStatus status) async {
    try {
      final updated = await _repo.changeStatus(taskId, status);
      _replaceTask(updated);
      return true;
    } on ApiException catch (error) {
      _ref.read(appErrorBusProvider).show(error.message);
      return false;
    }
  }

  void _replaceTask(Task task) {
    final index = state.tasks.indexWhere((t) => t.id == task.id);
    if (index < 0) return;
    final updated = [...state.tasks];
    updated[index] = task;
    state = state.copyWith(tasks: updated);
  }

  /// Убирает задачу из списка после удаления.
  void removeTask(String taskId) {
    state = state.copyWith(
      tasks: state.tasks.where((t) => t.id != taskId).toList(),
    );
  }

  /// Реалтайм: подставляем обновлённую задачу и добавляем новые.
  ///
  /// Формат событий различается: task.created приходит самой задачей,
  /// остальные — в объекте с полем task. Учитываем оба варианта.
  void _subscribe() {
    if (_ref.read(serverUrlProvider).isEmpty) return;
    _subscription = _ref.read(realtimeProvider).events.listen((event) {
      if (!event.isTaskChange) return;
      final data = event.data;

      if (event.type == 'task.deleted') {
        final id = data['task_id']?.toString();
        if (id != null) removeTask(id);
        return;
      }

      final payload = event.type == 'task.created'
          ? data
          : (data['task'] is Map ? data['task'] as Map : null);
      if (payload == null) return;

      final Task task;
      try {
        task = Task.fromJson(payload.cast<String, dynamic>());
      } catch (_) {
        return;
      }

      final known = state.tasks.any((t) => t.id == task.id);
      if (known) {
        _replaceTask(task);
        return;
      }

      // Новая задача от коллеги показывается, только если список не
      // сужен фильтром: иначе сотрудник увидит то, чего не искал.
      if (state.filter.isEmpty) {
        state = state.copyWith(
          tasks: [task, ...state.tasks],
          total: (state.total ?? state.tasks.length) + 1,
        );
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final taskListProvider = StateNotifierProvider<TaskListNotifier, TaskListState>(
  TaskListNotifier.new,
);

/// Карточка задачи с комментариями и историей.
class TaskDetailState {
  const TaskDetailState({
    this.task,
    this.isLoading = false,
    this.error,
    this.isSubmitting = false,
  });

  final Task? task;
  final bool isLoading;
  final String? error;
  final bool isSubmitting;

  TaskDetailState copyWith({
    Task? task,
    bool? isLoading,
    Object? error = _sentinel,
    bool? isSubmitting,
  }) =>
      TaskDetailState(
        task: task ?? this.task,
        isLoading: isLoading ?? this.isLoading,
        error: identical(error, _sentinel) ? this.error : error as String?,
        isSubmitting: isSubmitting ?? this.isSubmitting,
      );
}

class TaskDetailNotifier extends StateNotifier<TaskDetailState> {
  TaskDetailNotifier(this._ref, this.taskId) : super(const TaskDetailState()) {
    load();
  }

  final Ref _ref;
  final String taskId;

  TasksRepository get _repo => _ref.read(tasksRepositoryProvider);

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final task = await _repo.get(taskId);
      state = state.copyWith(task: task, isLoading: false);
    } on ApiException catch (error) {
      state = state.copyWith(isLoading: false, error: error.message);
    }
  }

  Future<bool> setStatus(TaskStatus status, {String? comment}) async {
    state = state.copyWith(isSubmitting: true);
    try {
      final task = await _repo.changeStatus(taskId, status, comment: comment);
      state = state.copyWith(task: task, isSubmitting: false);
      // Комментарий мог добавиться — обновляем карточку целиком.
      if (comment != null && comment.isNotEmpty) {
        await load();
      }
      return true;
    } on ApiException catch (error) {
      state = state.copyWith(isSubmitting: false);
      _ref.read(appErrorBusProvider).show(error.message);
      return false;
    }
  }

  Future<bool> addComment({
    String? body,
    List<Attachment> attachments = const [],
    bool isWorkReport = false,
  }) async {
    state = state.copyWith(isSubmitting: true);
    try {
      await _repo.addComment(
        taskId,
        body: body,
        attachmentIds: attachments.map((a) => a.id).toList(),
        isWorkReport: isWorkReport,
      );
      await load();
      state = state.copyWith(isSubmitting: false);
      return true;
    } on ApiException catch (error) {
      state = state.copyWith(isSubmitting: false);
      _ref.read(appErrorBusProvider).show(error.message);
      return false;
    }
  }

  Future<bool> assign({String? assigneeId, DateTime? dueAt}) async {
    try {
      final task = await _repo.assign(
        taskId,
        assigneeId: assigneeId,
        dueAt: dueAt,
      );
      state = state.copyWith(task: task);
      return true;
    } on ApiException catch (error) {
      _ref.read(appErrorBusProvider).show(error.message);
      return false;
    }
  }
}

final taskDetailProvider =
    StateNotifierProvider.family<TaskDetailNotifier, TaskDetailState, String>(
        TaskDetailNotifier.new);

/// Список сотрудников для управления отделом.
class DirectoryState {
  const DirectoryState({
    this.users = const [],
    this.roles = const [],
    this.isLoading = false,
    this.error,
    this.search = '',
  });

  final List<AppUser> users;
  final List<Role> roles;
  final bool isLoading;
  final String? error;
  final String search;

  DirectoryState copyWith({
    List<AppUser>? users,
    List<Role>? roles,
    bool? isLoading,
    Object? error = _sentinel,
    String? search,
  }) =>
      DirectoryState(
        users: users ?? this.users,
        roles: roles ?? this.roles,
        isLoading: isLoading ?? this.isLoading,
        error: identical(error, _sentinel) ? this.error : error as String?,
        search: search ?? this.search,
      );
}

class DirectoryNotifier extends StateNotifier<DirectoryState> {
  DirectoryNotifier(this._ref) : super(const DirectoryState()) {
    load();
  }

  final Ref _ref;

  DirectoryRepository get _repo => _ref.read(directoryRepositoryProvider);

  Future<void> load({String? search}) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      search: search ?? state.search,
    );
    try {
      final users = await _repo.users(search: search ?? state.search);
      final roles = await _repo.roles();
      state = state.copyWith(
        users: users,
        roles: roles,
        isLoading: false,
      );
    } on ApiException catch (error) {
      state = state.copyWith(isLoading: false, error: error.message);
    }
  }

  Future<({AppUser user, String? temporaryPassword})?> createUser({
    required String username,
    required String fullName,
    required List<String> roleIds,
    String? phone,
  }) async {
    try {
      final result = await _repo.createUser(
        username: username,
        fullName: fullName,
        roleIds: roleIds,
        phone: phone,
      );
      await load();
      return result;
    } on ApiException catch (error) {
      _ref.read(appErrorBusProvider).show(error.message);
      return null;
    }
  }

  Future<bool> setActive(String userId, bool active) async {
    try {
      if (active) {
        await _repo.activateUser(userId);
      } else {
        await _repo.deactivateUser(userId);
      }
      await load();
      return true;
    } on ApiException catch (error) {
      _ref.read(appErrorBusProvider).show(error.message);
      return false;
    }
  }

  Future<Role?> createRole({
    required String title,
    required List<String> permissions,
  }) async {
    try {
      final role = await _repo.createRole(
        title: title,
        permissions: permissions,
      );
      await load();
      return role;
    } on ApiException catch (error) {
      _ref.read(appErrorBusProvider).show(error.message);
      return null;
    }
  }

  Future<bool> updateRolePermissions(
      String roleId, List<String> permissions) async {
    try {
      await _repo.updateRole(roleId, permissions: permissions);
      await load();
      return true;
    } on ApiException catch (error) {
      _ref.read(appErrorBusProvider).show(error.message);
      return false;
    }
  }
}

final directoryProvider =
    StateNotifierProvider<DirectoryNotifier, DirectoryState>(
  DirectoryNotifier.new,
);

/// Список чатов.
class ChatListState {
  const ChatListState({
    this.chats = const [],
    this.isLoading = false,
    this.error,
  });

  final List<Chat> chats;
  final bool isLoading;
  final String? error;

  int get totalUnread =>
      chats.fold<int>(0, (sum, chat) => sum + chat.unreadCount);
}

class ChatListNotifier extends StateNotifier<ChatListState> {
  ChatListNotifier(this._ref) : super(const ChatListState()) {
    load();
    _subscribe();
  }

  final Ref _ref;
  StreamSubscription<dynamic>? _subscription;

  ChatRepository get _repo => _ref.read(chatRepositoryProvider);

  Future<void> load() async {
    state = ChatListState(
      chats: state.chats,
      isLoading: state.chats.isEmpty,
      error: state.error,
    );
    try {
      final chats = await _repo.chats();
      state = ChatListState(chats: chats, isLoading: false);
      _ref.read(unreadProvider.notifier).refresh();
    } on ApiException catch (error) {
      state = ChatListState(
        chats: state.chats,
        isLoading: false,
        error: error.message,
      );
    }
  }

  void clearUnread(String chatId) {
    state = ChatListState(
      chats: state.chats
          .map(
            (c) => c.id == chatId
                ? Chat(
                    id: c.id,
                    kind: c.kind,
                    title: c.title,
                    avatarUrl: c.avatarUrl,
                    members: c.members,
                    lastMessage: c.lastMessage,
                    lastMessageAt: c.lastMessageAt,
                    unreadCount: 0,
                    isAdmin: c.isAdmin,
                    isMuted: c.isMuted,
                  )
                : c,
          )
          .toList(),
      isLoading: false,
      error: state.error,
    );
  }

  void _subscribe() {
    if (_ref.read(serverUrlProvider).isEmpty) return;
    _subscription = _ref.read(realtimeProvider).events.listen((event) {
      if (event.isMessage) {
        final message = event.message;
        if (message != null) {
          _upsertMessage(message);
        }
      } else if (event.isMessageDeleted) {
        final chatId = event.data['chat_id']?.toString();
        if (chatId != null) {
          unawaited(load());
        }
      }
    });
  }

  /// Новое сообщение: обновляем превью и счётчик непрочитанных.
  void _upsertMessage(ChatMessage message) {
    final myId = _ref.read(currentUserProvider)?.id;
    final index = state.chats.indexWhere((c) => c.id == message.chatId);
    if (index < 0) {
      // Сообщение из чата, которого ещё нет в списке: подгружаем список.
      unawaited(load());
      return;
    }

    final chat = state.chats[index];
    final updated = Chat(
      id: chat.id,
      kind: chat.kind,
      title: chat.title,
      avatarUrl: chat.avatarUrl,
      members: chat.members,
      lastMessage: message,
      lastMessageAt: message.createdAt,
      unreadCount:
          message.sender?.id == myId ? chat.unreadCount : chat.unreadCount + 1,
      isAdmin: chat.isAdmin,
      isMuted: chat.isMuted,
    );

    final chats = [...state.chats]..[index] = updated;
    // Сверху — чат с самым свежим сообщением.
    chats.sort(
      (a, b) => (b.lastMessageAt ?? DateTime(0)).compareTo(
        a.lastMessageAt ?? DateTime(0),
      ),
    );
    state = ChatListState(chats: chats, isLoading: false);

    final unread = _ref.read(unreadProvider.notifier);
    if (message.sender?.id != myId) {
      unread.refresh();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final chatListProvider = StateNotifierProvider<ChatListNotifier, ChatListState>(
  ChatListNotifier.new,
);

/// Сообщения одного чата.
class MessagesState {
  const MessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isSending = false,
    this.error,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ChatMessage> messages;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isSending;
  final String? error;
  final String? nextCursor;
  final bool hasMore;

  /// Сообщения в порядке от старых к новым — так их показывает список.
  List<ChatMessage> get ordered {
    final sorted = [...messages]..sort((a, b) => a.seq.compareTo(b.seq));
    return sorted;
  }

  int get maxSeq => messages.isEmpty
      ? 0
      : messages.map((m) => m.seq).reduce((a, b) => a > b ? a : b);

  MessagesState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isSending,
    Object? error = _sentinel,
    String? nextCursor,
    bool? hasMore,
  }) =>
      MessagesState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        isSending: isSending ?? this.isSending,
        error: identical(error, _sentinel) ? this.error : error as String?,
        nextCursor: nextCursor ?? this.nextCursor,
        hasMore: hasMore ?? this.hasMore,
      );
}

class MessagesNotifier extends StateNotifier<MessagesState> {
  MessagesNotifier(this._ref, this.chatId) : super(const MessagesState()) {
    load();
    _subscribe();
  }

  final Ref _ref;
  final String chatId;
  StreamSubscription<dynamic>? _subscription;

  ChatRepository get _repo => _ref.read(chatRepositoryProvider);

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _repo.messages(chatId);
      state = MessagesState(
        messages: page.items,
        isLoading: false,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );
      _markRead();
    } on ApiException catch (error) {
      state = state.copyWith(isLoading: false, error: error.message);
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore) return;
    final cursor = state.nextCursor;
    if (cursor == null) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repo.messages(chatId, beforeSeq: cursor);
      final known = state.messages.map((m) => m.id).toSet();
      state = state.copyWith(
        messages: [
          ...state.messages,
          ...page.items.where((m) => !known.contains(m.id)),
        ],
        isLoadingMore: false,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );
    } on ApiException {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Добавляет сообщение, не дожидаясь ответа: отправка должна ощущаться мгновенно.
  void addPending(ChatMessage message) {
    state = state.copyWith(
      messages: [message, ...state.messages],
      isSending: true,
    );
  }

  /// Подтверждает отправку: временный пузырь заменяется настоящим.
  ///
  /// Замена идёт по идентификатору, а не добавление: событие
  /// message.created приходит по сокету раньше ответа HTTP, и при
  /// простом добавлении сообщение показывалось бы дважды.
  void confirmSent(ChatMessage message, {String? localId}) {
    final messages = [...state.messages];

    final realIndex = messages.indexWhere((m) => m.id == message.id);
    if (realIndex >= 0) {
      messages[realIndex] = message;
      state = state.copyWith(messages: messages, isSending: false);
      return;
    }

    if (localId != null) {
      final tempIndex = messages.indexWhere((m) => m.id == localId);
      if (tempIndex >= 0) {
        messages[tempIndex] = message;
        state = state.copyWith(messages: messages, isSending: false);
        return;
      }
    }

    state = state.copyWith(
      messages: [...messages, message],
      isSending: false,
    );
  }

  void failSending(String localId) {
    state = state.copyWith(
      messages: state.messages
          .map(
            (m) => m.id == localId
                ? ChatMessage(
                    id: m.id,
                    chatId: m.chatId,
                    seq: m.seq,
                    kind: m.kind,
                    status: 'failed',
                    body: m.body,
                    sender: m.sender,
                    attachment: m.attachment,
                    createdAt: m.createdAt,
                  )
                : m,
          )
          .toList(),
      isSending: false,
    );
  }

  Future<bool> sendText(String body, {String? replyToId}) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return false;

    final myId = _ref.read(currentUserProvider)?.id;
    final me = _ref.read(currentUserProvider);
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';

    addPending(
      ChatMessage(
        id: localId,
        chatId: chatId,
        seq: state.maxSeq + 1,
        kind: 'text',
        status: 'sending',
        body: trimmed,
        sender: me == null
            ? null
            : UserBrief(
                id: myId ?? '',
                username: me.username,
                fullName: me.fullName,
                avatarUrl: me.avatarUrl,
              ),
        createdAt: DateTime.now(),
      ),
    );

    try {
      final sent = await _repo.sendText(
        chatId,
        body: trimmed,
        replyToId: replyToId,
      );
      confirmSent(sent, localId: localId);
      return true;
    } on ApiException catch (error) {
      failSending(localId);
      _ref.read(appErrorBusProvider).show(error.message);
      return false;
    }
  }

  Future<bool> sendVoice({
    required List<int> bytes,
    required String filename,
    required double durationSec,
  }) async {
    final myId = _ref.read(currentUserProvider)?.id;
    final me = _ref.read(currentUserProvider);
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';

    addPending(
      ChatMessage(
        id: localId,
        chatId: chatId,
        seq: state.maxSeq + 1,
        kind: 'voice',
        status: 'sending',
        sender: me == null
            ? null
            : UserBrief(
                id: myId ?? '',
                username: me.username,
                fullName: me.fullName,
              ),
        voiceDurationSec: durationSec,
        createdAt: DateTime.now(),
      ),
    );

    try {
      final sent = await _repo.sendVoice(
        chatId,
        file: UploadFile(
          name: filename,
          bytes: bytes,
          mimeType: 'audio/mp4',
        ),
        durationSec: durationSec,
      );
      confirmSent(sent, localId: localId);
      return true;
    } on ApiException catch (error) {
      failSending(localId);
      _ref.read(appErrorBusProvider).show(error.message);
      return false;
    }
  }

  Future<bool> sendFile({
    required List<int> bytes,
    required String filename,
    String? mimeType,
    String? body,
  }) async {
    try {
      final sent = await _repo.sendFile(
        chatId,
        file: UploadFile(
          name: filename,
          bytes: bytes,
          mimeType: mimeType ?? 'application/octet-stream',
        ),
        body: body,
      );
      confirmSent(sent);
      return true;
    } on ApiException catch (error) {
      _ref.read(appErrorBusProvider).show(error.message);
      return false;
    }
  }

  /// Отмечает прочитанными через сокет: не ждём ответа сервера.
  void _markRead() {
    final seq = state.maxSeq;
    if (seq <= 0) return;
    _ref.read(realtimeProvider).markRead(chatId, seq);
    _ref.read(chatListProvider.notifier).clearUnread(chatId);
  }

  void _subscribe() {
    if (_ref.read(serverUrlProvider).isEmpty) return;
    _subscription = _ref.read(realtimeProvider).events.listen((event) {
      if (event.isTranscriptReady) {
        _applyTranscript(event.data);
        return;
      }
      if (!event.isMessage) return;

      final message = event.message;
      if (message == null || message.chatId != chatId) return;

      if (state.messages.any((m) => m.id == message.id)) {
        _replace(message);
        return;
      }
      state = state.copyWith(messages: [...state.messages, message]);
      _markRead();
    });
  }

  /// Подставляет готовую расшифровку в голосовое сообщение.
  void _applyTranscript(Map<String, dynamic> data) {
    final messageId = data['message_id']?.toString();
    final transcript = data['transcript'];
    if (messageId == null || transcript is! Map) return;

    final parsed = Transcript.fromJson(transcript.cast<String, dynamic>());
    state = state.copyWith(
      messages: state.messages
          .map(
            (m) => m.id == messageId
                ? ChatMessage(
                    id: m.id,
                    chatId: m.chatId,
                    seq: m.seq,
                    kind: m.kind,
                    status: m.status,
                    body: m.body,
                    sender: m.sender,
                    attachment: m.attachment,
                    transcript: parsed,
                    transcriptText: parsed.text,
                    voiceDurationSec: m.voiceDurationSec,
                    replyToId: m.replyToId,
                    editedAt: m.editedAt,
                    deletedAt: m.deletedAt,
                    createdAt: m.createdAt,
                  )
                : m,
          )
          .toList(),
    );
  }

  void _replace(ChatMessage message) {
    state = state.copyWith(
      messages:
          state.messages.map((m) => m.id == message.id ? message : m).toList(),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final messagesProvider =
    StateNotifierProvider.family<MessagesNotifier, MessagesState, String>(
        MessagesNotifier.new);

/// Отчёты для рабочего пространства главы.
class ReportsState {
  const ReportsState({
    this.summary,
    this.load = const [],
    this.isLoading = false,
    this.error,
  });

  final TaskSummary? summary;
  final List<UserLoad> load;
  final bool isLoading;
  final String? error;

  ReportsState copyWith({
    TaskSummary? summary,
    List<UserLoad>? load,
    bool? isLoading,
    Object? error = _sentinel,
  }) =>
      ReportsState(
        summary: summary ?? this.summary,
        load: load ?? this.load,
        isLoading: isLoading ?? this.isLoading,
        error: identical(error, _sentinel) ? this.error : error as String?,
      );
}

class ReportsNotifier extends StateNotifier<ReportsState> {
  ReportsNotifier(this._ref) : super(const ReportsState()) {
    load();
  }

  final Ref _ref;

  ReportsRepository get _repo => _ref.read(reportsRepositoryProvider);

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final summary = await _repo.taskSummary();
      final load = await _repo.userLoad();
      state = state.copyWith(
        summary: summary,
        load: load,
        isLoading: false,
      );
    } on ApiException catch (error) {
      state = state.copyWith(isLoading: false, error: error.message);
    }
  }
}

final reportsProvider = StateNotifierProvider<ReportsNotifier, ReportsState>(
  ReportsNotifier.new,
);
