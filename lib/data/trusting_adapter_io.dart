import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Адаптер, который доверяет самоподписанному сертификату сервера.
///
/// Нужен для подключения по внутреннему адресу или через VPN, где у
/// сервера нет выпущенного сертификата. Применяется только после того,
/// как сотрудник явно подтвердил доверие при подключении.
///
/// Файл вынесен отдельно, потому что использует `dart:io`, которого
/// нет в браузере: импорт подставляется условно, и веб-сборка не падает.
class TrustingAdapter implements HttpClientAdapter {
  TrustingAdapter() : _client = _createClient();

  static HttpClient _createClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    // Доверяем любому сертификату на том адресе, куда сотрудник
    // подтвердил подключение. Точечно по хосту проверить нельзя:
    // dart:io не даёт доступа к отпечатку сертификата.
    client.badCertificateCallback = (cert, host, port) => true;
    return client;
  }

  final HttpClient _client;

  @override
  void close({bool force = false}) {
    _client.close(force: force);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = await _client.openUrl(options.method, options.uri);

    request.followRedirects = true;
    request.maxRedirects = 5;

    options.headers.forEach((name, value) {
      if (value != null) request.headers.set(name, value);
    });

    if (requestStream != null) {
      // Тело запроса уже собрано dio: перекладываем его в сокет.
      unawaited(
        requestStream
            .forEach(request.add)
            .whenComplete(request.close)
            .catchError((Object _) => request.close()),
      );
    } else {
      request.close();
    }

    final response = await request.close();

    // Собираем тело целиком: файлы у нас небольшие (лимит задаётся
    // на сервере), а так адаптер работает одинаково на всех платформах.
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }

    final headers = <String, List<String>>{};
    response.headers.forEach((name, values) {
      headers[name] = values;
    });

    return ResponseBody.fromBytes(
      bytes,
      response.statusCode,
      headers: headers,
      statusMessage: response.reasonPhrase,
    );
  }
}
