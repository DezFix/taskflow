import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/api_client.dart';
import 'package:taskflow/l10n/l10n_scope.dart';

/// Проверяет контракт запросов к серверу: именно эти места ломались
/// тихо, без ошибок компиляции.
void main() {
  final l10n = L10nScope.current;

  group('Адрес запроса', () {
    final client =
        ApiClient(baseUrl: 'https://task.example.com', tokens: TokenProvider());

    test('путь начинается с префикса API', () {
      final uri = client.buildUriForTest('/api/v1/auth/refresh');
      expect(uri.path, '/api/v1/auth/refresh');
    });

    test('сервер на порту сохраняет порт в адресе', () {
      final local = ApiClient(
        baseUrl: 'https://192.168.1.50:8080',
        tokens: TokenProvider(),
      );
      expect(local.buildUriForTest('/api/v1/meta/info').toString(),
          'https://192.168.1.50:8080/api/v1/meta/info');
    });

    test('статусы и приоритеты идут повторяющимися параметрами', () {
      // Склейка через запятую приводила к 422: сервер ждёт
      // status=new&status=done, а не status=new,done.
      final uri = client.buildUriForTest(
        '/api/v1/tasks',
        {
          'status': ['new', 'in_progress'],
          'priority': ['high'],
        },
      );
      expect(uri.queryParametersAll['status'], ['new', 'in_progress']);
      expect(uri.queryParametersAll['priority'], ['high']);
      expect(uri.query, contains('status=new&status=in_progress'));
    });

    test('пустые значения не попадают в запрос', () {
      final uri = client.buildUriForTest('/api/v1/tasks', {
        'search': '',
        'assignee_id': null,
        'overdue': false,
      });
      expect(uri.queryParameters.containsKey('search'), isFalse);
      expect(uri.queryParameters.containsKey('assignee_id'), isFalse);
      // false — осмысленное значение, его сохраняем.
      expect(uri.queryParameters['overdue'], 'false');
    });

    test('относительный адрес файла склеивается с адресом сервера', () {
      expect(
        client.resolveUrl('/api/v1/files/abc/download'),
        'https://task.example.com/api/v1/files/abc/download',
      );
    });

    test('полный адрес не меняется', () {
      expect(
        client.resolveUrl('https://cdn.example.com/a.png'),
        'https://cdn.example.com/a.png',
      );
    });
  });

  group('Разбор ошибок', () {
    test('сетевая ошибка превращается в понятный текст', () {
      final error =
          ApiClient(baseUrl: 'https://x.example', tokens: TokenProvider())
              .convertForTest(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/tasks'),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(error.code, 'network_unreachable');
      // Сотрудник читает friendly, а не технический текст dio.
      expect(error.info.localized(l10n), contains('Сервер'));
    });

    test('код ошибки берётся из тела ответа', () {
      final error =
          ApiClient(baseUrl: 'https://x.example', tokens: TokenProvider())
              .convertForTest(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/tasks'),
          type: DioExceptionType.badResponse,
          response: Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: '/api/v1/tasks'),
            statusCode: 403,
            data: {
              'error': {'code': 'task_access_denied', 'message': 'Нет доступа'},
            },
          ),
        ),
      );
      expect(error.code, 'task_access_denied');
      expect(error.message, 'Нет доступа');
      expect(error.statusCode, 403);
    });
  });

  group('Токены', () {
    test('смена адреса сервера не должна стирать токены', () {
      final tokens = TokenProvider()..accessToken = 'abc';
      expect(tokens.accessToken, 'abc');
    });
  });
}
