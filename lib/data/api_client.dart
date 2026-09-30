/// HTTP-клиент TaskFlow: авторизация, обновление токена, загрузка файлов.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'models.dart';
import 'trusting_adapter_stub.dart'
    if (dart.library.io) 'trusting_adapter_io.dart' as adapter;

/// Ошибка сети или сервера с понятным описанием для интерфейса.
class ApiException implements Exception {
  ApiException(this.info, {this.statusCode});

  final ApiErrorInfo info;
  final int? statusCode;

  String get message => info.friendly;
  String get code => info.code;

  bool get isUnauthorized => statusCode == 401;

  /// Ошибка, при которой стоит предложить повторить попытку.
  bool get isRetryable =>
      code == 'network_unreachable' ||
      code == 'connection_timeout' ||
      code == 'internal_error' ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;

  @override
  String toString() => 'ApiException($code): ${info.message}';
}

/// Файл для отправки: имя, содержимое, тип.
class UploadFile {
  const UploadFile({
    required this.name,
    required this.bytes,
    this.mimeType = 'application/octet-stream',
  });

  final String name;
  final List<int> bytes;
  final String mimeType;
}

/// Файл, выбранный на устройстве: читать будем при отправке.
class FileHandle {
  const FileHandle({
    required this.name,
    required this.path,
    required this.sizeBytes,
    this.mimeType,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final String? mimeType;
}

/// Параметры фильтрации списка задач.
class TaskFilter {
  const TaskFilter({
    this.search = '',
    this.statuses = const [],
    this.priorities = const [],
    this.assigneeId,
    this.overdueOnly = false,
    this.showArchived = false,
  });

  final String search;
  final List<TaskStatus> statuses;
  final List<TaskPriority> priorities;
  final String? assigneeId;
  final bool overdueOnly;
  final bool showArchived;

  bool get isEmpty =>
      search.isEmpty &&
      statuses.isEmpty &&
      priorities.isEmpty &&
      assigneeId == null &&
      !overdueOnly &&
      !showArchived;

  /// Сколько фильтров активно — для бейджа на кнопке.
  int get activeCount {
    var count = 0;
    if (search.isNotEmpty) count++;
    if (statuses.isNotEmpty) count++;
    if (priorities.isNotEmpty) count++;
    if (assigneeId != null) count++;
    if (overdueOnly) count++;
    if (showArchived) count++;
    return count;
  }

  TaskFilter copyWith({
    String? search,
    List<TaskStatus>? statuses,
    List<TaskPriority>? priorities,
    String? assigneeId,
    bool clearAssignee = false,
    bool? overdueOnly,
    bool? showArchived,
  }) =>
      TaskFilter(
        search: search ?? this.search,
        statuses: statuses ?? this.statuses,
        priorities: priorities ?? this.priorities,
        assigneeId: clearAssignee ? null : (assigneeId ?? this.assigneeId),
        overdueOnly: overdueOnly ?? this.overdueOnly,
        showArchived: showArchived ?? this.showArchived,
      );
}

/// Токены, которые клиент умеет обновлять сам.
class TokenProvider {
  TokenProvider({this.onTokensRenewed, this.onSessionLost});

  String? accessToken;
  String? refreshToken;

  /// Вызывается, когда сервер выдал новую пару токенов.
  Future<void> Function(String access, String refresh)? onTokensRenewed;

  /// Вызывается, когда refresh не помог и пора показывать экран входа.
  Future<void> Function()? onSessionLost;

  bool get hasSession => (accessToken ?? '').isNotEmpty;
}

/// Обёртка над Dio со всеми перехватами ошибок в одном месте.
class ApiClient {
  ApiClient({required this.baseUrl, required this.tokens, Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 60),
                headers: {'Accept': 'application/json'},
                // Проверку сертификата делаем сами: в офисной сети
                // сертификат часто самоподписанный, и решение принимает сотрудник.
                validateStatus: (status) => status != null && status < 500,
              ),
            );

  final String baseUrl;
  final TokenProvider tokens;
  final Dio _dio;

  bool _refreshing = false;
  Future<bool>? _refreshFuture;

  /// Разрешает недоверенный сертификат для этого сервера.
  /// Включается только явным решением пользователя.
  void allowSelfSignedCertificate() {
    _dio.httpClientAdapter = adapter.TrustingAdapter();
  }

  Dio get dio => _dio;

  String? get accessToken => tokens.accessToken;

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer ${tokens.accessToken ?? ''}',
      };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(baseUrl);
    final merged = <String, dynamic>{...?query};
    // Пустые значения серверу не нужны: убираем, чтобы не путать фильтры.
    merged.removeWhere((_, value) => value == null || value == '');

    // Списки (статусы, приоритеты) отправляем повторяющимися параметрами:
    // сервер ожидает status=new&status=done. Склейка через запятую
    // привела бы к ошибке валидации.
    final params = <String, dynamic>{};
    merged.forEach((key, value) {
      if (value is Iterable) {
        params[key] = value.map((item) => '$item').toList();
      } else {
        params[key] = '$value';
      }
    });

    return base.replace(
      path: '${base.path}$path',
      queryParameters: params.isEmpty ? null : params,
    );
  }

  // --- Инфраструктура запросов ---

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    return send(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        _uri(path, query).toString(),
        options: Options(headers: _authHeaders),
      );
      return _unwrap(response);
    });
  }

  Future<List<dynamic>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    return send(() async {
      final response = await _dio.get<List<dynamic>>(
        _uri(path, query).toString(),
        options: Options(headers: _authHeaders),
      );
      return _unwrapList(response);
    });
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return send(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        _uri(path).toString(),
        data: body,
        options: Options(headers: _authHeaders),
      );
      return _unwrap(response);
    });
  }

  Future<Map<String, dynamic>> postPublic(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return send(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        _uri(path).toString(),
        data: body,
      );
      return _unwrap(response);
    });
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return send(() async {
      final response = await _dio.patch<Map<String, dynamic>>(
        _uri(path).toString(),
        data: body,
        options: Options(headers: _authHeaders),
      );
      return _unwrap(response);
    });
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return send(() async {
      final response = await _dio.put<Map<String, dynamic>>(
        _uri(path).toString(),
        data: body,
        options: Options(headers: _authHeaders),
      );
      return _unwrap(response);
    });
  }

  Future<void> delete(String path) async {
    await send(() async {
      final response = await _dio.delete<Map<String, dynamic>>(
        _uri(path).toString(),
        options: Options(headers: _authHeaders),
      );
      _unwrap(response);
      return <String, dynamic>{};
    });
  }

  /// Отправка файла с необязательным текстовым подписью.
  Future<Map<String, dynamic>> upload(
    String path, {
    required UploadFile file,
    Map<String, String> fields = const {},
  }) async {
    return send(() async {
      final form = FormData();
      form.files.add(
        MapEntry(
          'file',
          MultipartFile.fromBytes(file.bytes, filename: file.name),
        ),
      );
      fields.forEach((key, value) => form.fields.add(MapEntry(key, value)));

      final response = await _dio.post<Map<String, dynamic>>(
        _uri(path).toString(),
        data: form,
        options: Options(headers: _authHeaders),
      );
      return _unwrap(response);
    });
  }

  /// Скачивает файл с авторизацией и возвращает его содержимое.
  ///
  /// Нужен там, где браузер или Image.network не смогут приложить
  /// заголовок с токеном: аватары, выгрузка CSV, прослушивание голоса.
  Future<Uint8List> getBytes(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    return send(() async {
      final response = await _dio.get<Uint8List>(
        _uri(path, query).toString(),
        options: Options(
          headers: _authHeaders,
          responseType: ResponseType.bytes,
        ),
      );
      final data = response.data;
      if (data == null) {
        throw ApiException(
          const ApiErrorInfo(code: 'empty_file', message: 'Файл пустой'),
        );
      }
      return data;
    });
  }

  /// Разрешает адрес файла на текущем сервере.
  String resolveUrl(String? relative) {
    if (relative == null || relative.isEmpty) return '';
    if (relative.startsWith('http://') || relative.startsWith('https://')) {
      return relative;
    }
    return '$baseUrl$relative';
  }

  /// Единая точка обработки ошибок и повторного входа.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiException {
      rethrow;
    } on _RefreshNeeded {
      // Служебный сигнал «токен протух» обязан выйти наружу: иначе
      // повторный запрос не произойдёт, а пользователь увидит
      // сообщение о непредвиденной ошибке.
      rethrow;
    } on DioException catch (error) {
      throw _convert(error);
    } catch (error) {
      throw ApiException(
        ApiErrorInfo(code: 'unknown', message: 'Непредвиденная ошибка: $error'),
      );
    }
  }

  /// Выполняет запрос, при протухшем токене обновляет его и повторяет.
  Future<T> send<T>(Future<T> Function() action) async {
    try {
      return await _guard(action);
    } on _RefreshNeeded {
      final renewed = await refreshTokens();
      if (!renewed) {
        throw ApiException(
          const ApiErrorInfo(
            code: 'token_expired',
            message: 'Сессия истекла, войдите заново',
          ),
          statusCode: 401,
        );
      }
      return _guard(action);
    }
  }

  dynamic _unwrap(Response<Map<String, dynamic>> response) {
    final status = response.statusCode ?? 0;
    final data = response.data;

    if (status >= 400) {
      // Токен протух: пробуем обновить и повторить запрос один раз.
      if (status == 401 && _canRefresh(data)) {
        throw _RefreshNeeded();
      }
      throw ApiException(
        ApiErrorInfo.parse(data),
        statusCode: status,
      );
    }
    return data ?? <String, dynamic>{};
  }

  List<dynamic> _unwrapList(Response<List<dynamic>> response) {
    final status = response.statusCode ?? 0;
    final data = response.data;

    if (status >= 400) {
      if (status == 401 && _canRefresh(data)) {
        throw _RefreshNeeded();
      }
      throw ApiException(
        ApiErrorInfo.parse(data),
        statusCode: status,
      );
    }
    return data ?? <dynamic>[];
  }

  /// Не пытаемся обновить токен, если сервер прямо отверг refresh.
  bool _canRefresh(Object? data) {
    if (!tokens.hasSession) return false;
    if ((tokens.refreshToken ?? '').isEmpty) return false;
    final code = Json.object(data)?['error'] is Map
        ? ((data as Map)['error'] as Map)['code']
        : null;
    return code != 'invalid_refresh' &&
        code != 'session_revoked' &&
        code != 'session_expired';
  }

  ApiException _convert(DioException error) {
    final type = error.type;
    final message = error.message ?? '';

    if (type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.sendTimeout ||
        type == DioExceptionType.receiveTimeout) {
      return ApiException(
        const ApiErrorInfo(
          code: 'connection_timeout',
          message: 'Сервер не отвечает вовремя',
        ),
      );
    }

    if (type == DioExceptionType.connectionError) {
      final text = message.toLowerCase();
      if (text.contains('certificate')) {
        return ApiException(
          const ApiErrorInfo(
            code: 'certificate_error',
            message: 'Сертификат сертификата сервера не вызывает доверия',
          ),
        );
      }
      if (text.contains('host') ||
          text.contains('lookup') ||
          text.contains('connect')) {
        return ApiException(
          const ApiErrorInfo(
            code: 'network_unreachable',
            message: 'Не удалось подключиться к серверу',
          ),
        );
      }
      return ApiException(
        const ApiErrorInfo(
          code: 'network_unreachable',
          message: 'Нет связи с сервером',
        ),
      );
    }

    if (type == DioExceptionType.badCertificate) {
      return ApiException(
        const ApiErrorInfo(
          code: 'certificate_error',
          message: 'Сертификат сервера не вызывает доверия',
        ),
      );
    }

    if (type == DioExceptionType.badResponse) {
      final status = error.response?.statusCode;
      return ApiException(
        ApiErrorInfo.parse(error.response?.data),
        statusCode: status,
      );
    }

    // Сетевая ошибка: сервер недоступен или адрес неверный.
    // Проверяем по типу dio, а не по SocketException из dart:io:
    // в браузере такого класса нет, и проверка не скомпилировалась бы.
    final isNetworkError = error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.error.runtimeType.toString() == 'SocketException' ||
        error.error.runtimeType.toString() == 'HttpException';

    if (isNetworkError) {
      return ApiException(
        const ApiErrorInfo(
          code: 'network_unreachable',
          message: 'Нет связи с сервером',
        ),
      );
    }

    return ApiException(
      ApiErrorInfo(code: 'unknown', message: message),
    );
  }

  // --- Служебное: используется только в тестах -------------------------
  // Открываем наружу то, что иначе нечем проверить: правила сборки
  // адреса и разбора ошибок ломались молча, без сбоя компиляции.

  /// Собирает адрес запроса по тем же правилам, что и реальные вызовы.
  @visibleForTesting
  Uri buildUriForTest(String path, [Map<String, dynamic>? query]) =>
      _uri(path, query);

  /// Преобразует ошибку dio в ApiException.
  @visibleForTesting
  ApiException convertForTest(DioException error) => _convert(error);

  /// Обновляет пару токенов. Параллельные вызовы разделяют один запрос.
  Future<bool> refreshTokens() {
    if (_refreshFuture != null) return _refreshFuture!;
    final future = _doRefresh();
    _refreshFuture = future;
    return future;
  }

  Future<bool> _doRefresh() async {
    if (_refreshing) return false;
    _refreshing = true;
    try {
      final refresh = tokens.refreshToken;
      if (refresh == null || refresh.isEmpty) {
        await _loseSession();
        return false;
      }

      final response = await _dio.post<Map<String, dynamic>>(
        // Путь с префиксом API: baseUrl содержит только адрес сервера.
        _uri('/api/v1/auth/refresh').toString(),
        data: {'refresh_token': refresh},
      );

      final status = response.statusCode ?? 0;
      if (status >= 400) {
        await _loseSession();
        return false;
      }

      final data = response.data ?? const <String, dynamic>{};
      final access = data['access_token']?.toString();
      final newRefresh = data['refresh_token']?.toString();
      if (access == null || newRefresh == null) {
        await _loseSession();
        return false;
      }

      tokens.accessToken = access;
      tokens.refreshToken = newRefresh;
      await tokens.onTokensRenewed?.call(access, newRefresh);
      return true;
    } catch (_) {
      await _loseSession();
      return false;
    } finally {
      _refreshing = false;
      _refreshFuture = null;
    }
  }

  Future<void> _loseSession() async {
    tokens.accessToken = null;
    tokens.refreshToken = null;
    await tokens.onSessionLost?.call();
  }
}

/// Внутреннее исключение: токен протух, запрос нужно повторить.
/// Наружу не выходит: его перехватывает [ApiClient.send].
class _RefreshNeeded implements Exception {
  const _RefreshNeeded();
}

/// Собирает ответы API в типизированные модели.
class ApiParsers {
  const ApiParsers._();

  static AppUser user(Map<String, dynamic> json) => AppUser.fromJson(json);

  static UserBrief userBrief(Map<String, dynamic> json) =>
      UserBrief.fromJson(json);

  static Task task(Map<String, dynamic> json) => Task.fromJson(json);

  static Paged<Task> tasks(Map<String, dynamic> json) =>
      Paged.fromJson(json, Task.fromJson);

  static Paged<ChatMessage> messages(Map<String, dynamic> json) =>
      Paged.fromJson(json, ChatMessage.fromJson);

  static Chat chat(Map<String, dynamic> json) => Chat.fromJson(json);

  static List<UserBrief> users(List<dynamic> data) =>
      data.map((e) => UserBrief.fromJson(e as Map<String, dynamic>)).toList();

  static List<AppUser> appUsers(List<dynamic> data) =>
      data.map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();

  static List<Task> taskList(List<dynamic> data) =>
      data.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();

  static List<Chat> chatList(List<dynamic> data) =>
      data.map((e) => Chat.fromJson(e as Map<String, dynamic>)).toList();

  static List<String> strings(List<dynamic> data) =>
      data.map((e) => e.toString()).toList();

  static List<Map<String, dynamic>> maps(List<dynamic> data) =>
      data.cast<Map<String, dynamic>>();

  static UserLoad load(Map<String, dynamic> json) => UserLoad.fromJson(json);

  static String encodeJson(Map<String, dynamic> value) => jsonEncode(value);
}
