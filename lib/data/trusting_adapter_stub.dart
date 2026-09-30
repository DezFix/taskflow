import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Заглушка для браузера.
///
/// В вебе сертификат сервера проверяет сам браузер, и обойти эту
/// проверку нельзя. Собственный сертификат там не применить, поэтому
/// подключение идёт обычным способом — с проверкой TLS.
class TrustingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw UnsupportedError(
      'Доверие к самоподписанному сертификату доступно только в мобильном '
      'приложении. В браузере сертификат проверяет сам браузер.',
    );
  }
}
