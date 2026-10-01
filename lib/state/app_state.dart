/// Состояние приложения: сервер, сессия, пользователь, реалтайм.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/realtime.dart';
import '../data/repositories.dart';
import '../data/storage.dart';
import 'controllers.dart';

/// Этап, на котором находится приложение.
enum AppStage {
  /// Проверяем сохранённые данные при запуске.
  loading,

  /// Просим адрес сервера.
  needsServer,

  /// Сервер выбран, но сотрудник ещё не вошёл.
  needsLogin,

  /// Сервер ещё не настроен: нужен мастер создания администратора.
  needsSetup,

  /// Вход выполнен, показываем рабочее пространство.
  ready,
}

/// Хранилище и настройки приложения. Создаётся один раз при старте.
final storageProvider = Provider<AppStorage>((ref) {
  throw UnimplementedError(
      'storageProvider должен быть переопределён при старте');
});

/// Язык интерфейса: null означает «как в системе».
///
/// Хранится отдельно от сервера, потому что выбор языка должен
/// переживать и смену адреса, и выход из учётной записи.
final localeCodeProvider = StateProvider<String?>((ref) {
  return ref.read(storageProvider).localeCode;
});

/// Текущий адрес сервера. Пустая строка — сервер ещё не выбран.
final serverUrlProvider = StateProvider<String>((ref) => '');

/// Активная сессия: адрес, токены, логин.
///
/// Отдельный контроллер вместо StateProvider: так состояние меняется
/// только через явный метод, а не записью в `.notifier.state` извне.
class SessionNotifier extends StateNotifier<StoredSession?> {
  SessionNotifier() : super(null);

  void set(StoredSession? session) => state = session;

  void clear() => state = null;
}

final sessionProvider = StateNotifierProvider<SessionNotifier, StoredSession?>(
  (_) => SessionNotifier(),
);

/// Обёртка над токенами, которой пользуется HTTP-клиент.
final tokenProviderProvider = Provider<TokenProvider>((ref) {
  final provider = TokenProvider(
    onTokensRenewed: (access, refresh) async {
      final session = ref.read(sessionProvider);
      final url = ref.read(serverUrlProvider);
      if (session != null && url.isNotEmpty) {
        final updated = StoredSession(
          serverUrl: url,
          accessToken: access,
          refreshToken: refresh,
          username: session.username,
          fullName: session.fullName,
        );
        await ref.read(storageProvider).saveSession(updated);
        ref.read(sessionProvider.notifier).set(updated);
      }
    },
    onSessionLost: () async {
      await ref.read(storageProvider).clearSession();
      ref.read(sessionProvider.notifier).clear();
      ref.read(currentUserProvider.notifier).setUser(null);
      ref.read(appStageProvider.notifier).setStage(AppStage.needsLogin);
    },
  );
  return provider;
});

/// HTTP-клиент. Пересоздаётся при смене адреса сервера.
final apiClientProvider = Provider<ApiClient>((ref) {
  final url = ref.watch(serverUrlProvider);
  final tokens = ref.watch(tokenProviderProvider);
  if (url.isEmpty) {
    throw StateError('Адрес сервера не задан');
  }
  final client = ApiClient(baseUrl: url, tokens: tokens);
  if (ref.read(storageProvider).trustsCertificate(url)) {
    // Сотрудник подтвердил отпечаток сертификата для этого сервера.
    client.allowSelfSignedCertificate();
  }
  ref.onDispose(client.dio.close);
  return client;
});

/// Текущий сотрудник с его правами.
class CurrentUserNotifier extends StateNotifier<AppUser?> {
  CurrentUserNotifier(this._ref) : super(null) {
    _tokens.accessToken = _ref.read(sessionProvider)?.accessToken;
    _tokens.refreshToken = _ref.read(sessionProvider)?.refreshToken;
  }

  final Ref _ref;
  late final TokenProvider _tokens = _ref.read(tokenProviderProvider);

  AuthRepository get _auth => AuthRepository(_ref.read(apiClientProvider));

  void setUser(AppUser? user) => state = user;

  /// Загружает профиль: нужен для списка прав при каждом запуске.
  Future<void> load() async {
    if ((_ref.read(sessionProvider)?.accessToken ?? '').isEmpty) {
      state = null;
      return;
    }
    try {
      state = await _auth.me();
    } on ApiException {
      state = null;
    }
  }

  Future<void> updateProfile(Map<String, dynamic> changes) async {
    state = await _auth.updateProfile(changes);
  }

  /// Выход: гасим сессию на сервере и чистим локально.
  Future<void> logout() async {
    await _auth.logout();
    final storage = _ref.read(storageProvider);
    await storage.clearSession();
    _ref.read(sessionProvider.notifier).clear();
    state = null;

    // Токены обнуляются до переподключения. Раньше они оставались в
    // памяти, и сокет поднимался со старым access-токеном: доступ-токен
    // на сервере проверяется только подписью, поэтому канал продолжал
    // работать после выхода и слать чужие сообщения в фоне.
    _ref.read(tokenProviderProvider)
      ..accessToken = ''
      ..refreshToken = '';
    _ref.read(realtimeProvider).disconnect();

    // Списки очищаются: иначе следующий сотрудник, вошедший в том же
    // приложении, первым кадром увидит задачи и сообщения предыдущего.
    _ref.invalidate(taskListProvider);
    _ref.invalidate(chatListProvider);
    _ref.invalidate(directoryProvider);
  }
}

final currentUserProvider =
    StateNotifierProvider<CurrentUserNotifier, AppUser?>(
  CurrentUserNotifier.new,
);

/// Управляет этапом приложения и входом.
class AppStageNotifier extends StateNotifier<AppStage> {
  AppStageNotifier(this._ref) : super(AppStage.loading) {
    _restore();
  }

  final Ref _ref;

  AppStorage get _storage => _ref.read(storageProvider);

  void setStage(AppStage stage) => state = stage;

  /// Восстанавливает состояние при запуске приложения.
  Future<void> _restore() async {
    final session = _storage.session;
    if (session == null || session.accessToken.isEmpty) {
      state = AppStage.needsServer;
      return;
    }

    _ref.read(serverUrlProvider.notifier).state = session.serverUrl;
    _ref.read(sessionProvider.notifier).set(session);
    _ref.read(tokenProviderProvider)
      ..accessToken = session.accessToken
      ..refreshToken = session.refreshToken;

    state = AppStage.needsLogin;
    // Пробуем восстановить вход, но не блокируем интерфейс: если сервер
    // недоступен, сотрудник увидит экран входа и сообщение об ошибке.
    try {
      await _ref.read(currentUserProvider.notifier).load();
      if (_ref.read(currentUserProvider) != null) {
        state = AppStage.ready;
        _ref.read(realtimeProvider).connect();
      }
    } on ApiException catch (error) {
      if (error.code == 'network_unreachable' ||
          error.code == 'connection_timeout') {
        _lastNetworkError = error;
      }
    }
  }

  /// Последняя сетевая ошибка: показывается на экране входа.
  ApiException? _lastNetworkError;

  ApiException? get lastNetworkError => _lastNetworkError;

  /// Подключается к серверу по указанному адресу.
  Future<ServerInfo> connectToServer(
    String rawUrl, {
    bool trustCertificate = false,
    String? label,
  }) async {
    final url = AppStorage.normalizeServerUrl(rawUrl);
    if (url.isEmpty) {
      // Текст подставит перевод по коду bad_url.
      throw ApiException(const ApiErrorInfo(code: 'bad_url'));
    }

    // Клиент настраиваем до проверки: доверие к сертификату включает
    // уже при первом обращении.
    _ref.read(serverUrlProvider.notifier).state = url;
    if (trustCertificate) {
      await _storage.trustCertificate(url);
    }

    final client = _ref.read(apiClientProvider);
    final info = await DirectoryRepositoryProbe(client).check(url);
    await _storage.rememberServer(url, label: label);
    await _storage.setActiveServer(url);
    return info;
  }

  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    final client = _ref.read(apiClientProvider);
    final result = await AuthRepository(client).login(
      identifier: identifier,
      password: password,
    );

    final url = _ref.read(serverUrlProvider);
    await _storage.saveSession(
      StoredSession(
        serverUrl: url,
        accessToken: result.tokens.accessToken,
        refreshToken: result.tokens.refreshToken,
        username: result.user.username,
        fullName: result.user.fullName,
      ),
    );
    await _storage.setLastUsername(result.user.username);
    _ref.read(sessionProvider.notifier).set(_storage.session);
    _ref.read(currentUserProvider.notifier).setUser(result.user);
    state = AppStage.ready;
    _ref.read(realtimeProvider).reconnect();
  }

  /// Выходит из сессии, но сохраняет адрес сервера.
  Future<void> logout() async {
    await _ref.read(currentUserProvider.notifier).logout();
    state = AppStage.needsLogin;
  }

  /// Возвращает сотрудника к экрану выбора сервера.
  Future<void> forgetServer() async {
    final url = _ref.read(serverUrlProvider);
    if (url.isNotEmpty) {
      await _storage.forgetServer(url);
    }
    await _storage.clearAll();
    _ref.read(serverUrlProvider.notifier).state = '';
    _ref.read(sessionProvider.notifier).clear();
    _ref.read(currentUserProvider.notifier).setUser(null);
    state = AppStage.needsServer;
  }
}

final appStageProvider = StateNotifierProvider<AppStageNotifier, AppStage>(
  AppStageNotifier.new,
);

/// Сохранённые адреса серверов для экрана выбора.
final savedServersProvider = Provider<List<ServerEntry>>((ref) {
  return ref.watch(storageProvider).servers;
});

/// Репозитории, готовые к работе.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

final directoryRepositoryProvider = Provider<DirectoryRepository>(
  (ref) => DirectoryRepository(ref.watch(apiClientProvider)),
);

final tasksRepositoryProvider = Provider<TasksRepository>(
  (ref) => TasksRepository(ref.watch(apiClientProvider)),
);

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(apiClientProvider)),
);

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(ref.watch(apiClientProvider)),
);

/// Канал реалтайма. Создаётся один раз на сервер.
final realtimeProvider = Provider<RealtimeChannel>((ref) {
  final url = ref.watch(serverUrlProvider);
  final tokens = ref.watch(tokenProviderProvider);
  if (url.isEmpty) {
    throw StateError('Адрес сервера не задан');
  }
  final channel = RealtimeChannel(
    baseUrl: url,
    tokenProvider: tokens,
  );
  ref.onDispose(channel.dispose);
  return channel;
});

/// Состояние соединения реалтайма для индикатора в интерфейсе.
final realtimeStatusProvider = StreamProvider<RealtimeStatus>((ref) {
  if (ref.read(serverUrlProvider).isEmpty) {
    return Stream<RealtimeStatus>.value(RealtimeStatus.disconnected);
  }
  return ref.watch(realtimeProvider).status;
});

/// Счётчик непрочитанных сообщений для бейджа.
class UnreadNotifier extends StateNotifier<int> {
  UnreadNotifier(this._ref) : super(0) {
    _load();
    _subscribe();
  }

  final Ref _ref;
  StreamSubscription<RealtimeEvent>? _subscription;

  void _load() {
    if ((_ref.read(sessionProvider)?.accessToken ?? '').isEmpty) return;
    ChatRepository(_ref.read(apiClientProvider))
        .unreadTotal()
        .then((value) => state = value)
        .catchError((_) => 0);
  }

  void _subscribe() {
    if (_ref.read(serverUrlProvider).isEmpty) return;
    final channel = _ref.read(realtimeProvider);
    _subscription = channel.events.listen((event) {
      if (!event.isMessage) return;
      final sender = event.data['sender'];
      final senderId = sender is Map ? sender['id']?.toString() : null;
      if (senderId != null && senderId == _ref.read(currentUserProvider)?.id) {
        // Своё сообщение не увеличивает счётчик.
        return;
      }
      state = state + 1;
    });
  }

  void refresh() => _load();

  void reset() => state = 0;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final unreadProvider = StateNotifierProvider<UnreadNotifier, int>(
  UnreadNotifier.new,
);

/// Помощник для проверки сервера до создания полноценного клиента.
class DirectoryRepositoryProbe {
  DirectoryRepositoryProbe(this.client);

  final ApiClient client;

  Future<ServerInfo> check(String url) async {
    // /meta/info отдаёт один объект, а не массив: getList здесь
    // всегда падал бы и подключиться к серверу было бы невозможно.
    final data = await client.get('/api/v1/meta/info');
    if (data.isEmpty) {
      // Адрес отвечает, но не похож на TaskFlow: перевод по коду.
      throw ApiException(const ApiErrorInfo(code: 'not_taskflow'));
    }
    return ServerInfo.fromJson(data.cast<String, dynamic>());
  }
}

/// Сообщения об ошибках, которые нужно показать сотруднику один раз.
class AppErrorBus {
  AppErrorBus._();

  static final instance = AppErrorBus._();

  final _controller = StreamController<String>.broadcast();
  Stream<String> get messages => _controller.stream;

  void show(String message) {
    if (message.isNotEmpty) _controller.add(message);
  }

  void showError(Object error) {
    if (error is ApiException) {
      show(error.message);
    } else {
      debugPrint('Необработанная ошибка: $error');
    }
  }
}

final appErrorBusProvider =
    Provider<AppErrorBus>((ref) => AppErrorBus.instance);
