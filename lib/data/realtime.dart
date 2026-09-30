/// WebSocket-канал реалтайма: сообщения, задачи, статусы расшифровки.
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'models.dart';

/// Событие с сервера.
class RealtimeEvent {
  const RealtimeEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;

  factory RealtimeEvent.parse(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return RealtimeEvent(
      decoded['type']?.toString() ?? 'unknown',
      (decoded['data'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  bool get isMessage => type == 'message.created' || type == 'message.updated';
  bool get isMessageDeleted => type == 'message.deleted';
  bool get isReadReceipt => type == 'message.read';
  bool get isTaskChange =>
      type == 'task.created' ||
      type == 'task.updated' ||
      type == 'task.deleted';
  bool get isTranscriptReady => type == 'transcript.ready';
  bool get isSessionRevoked => type == 'session.revoked';
  bool get isChatUpdate => type == 'chat.updated';

  /// Сообщение из события, если оно пришло.
  ChatMessage? get message {
    final id = data['id'];
    if (id == null) return null;
    try {
      return ChatMessage.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}

/// Состояние соединения для интерфейса.
enum RealtimeStatus { disconnected, connecting, connected }

/// Канал реалтайма с автопереподключением.
class RealtimeChannel {
  RealtimeChannel({required this.baseUrl, required this.tokenProvider});

  final String baseUrl;
  final TokenProvider tokenProvider;

  final _events = StreamController<RealtimeEvent>.broadcast();
  final _status = StreamController<RealtimeStatus>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  RealtimeStatus _current = RealtimeStatus.disconnected;
  bool _disposed = false;
  int _attempts = 0;

  /// События от сервера. Подписчик может отключиться и вернуться.
  Stream<RealtimeEvent> get events => _events.stream;

  /// Изменения состояния соединения: индикатор в интерфейсе.
  Stream<RealtimeStatus> get status => _status.stream;

  RealtimeStatus get currentStatus => _current;

  /// Подключается к каналу. Повторный вызов безопасен.
  void connect() {
    if (_disposed) return;
    if (_current != RealtimeStatus.disconnected) return;

    final token = tokenProvider.accessToken;
    if (token == null || token.isEmpty) return;

    _setStatus(RealtimeStatus.connecting);

    final wsUrl = _webSocketUrl(token);
    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel = channel;
      // Обработчики сверяются с текущим каналом: после переподключения
      // старый сокет может дослать onDone и закрыть новый.
      _subscription = channel.stream.listen(
        _onData,
        onError: (Object error) => _onError(channel, error),
        onDone: () => _onClosed(channel),
        cancelOnError: true,
      );
      _startHeartbeat();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onData(dynamic raw) {
    // Первое сообщение от сервера означает, что соединение установлено.
    if (_current != RealtimeStatus.connected) {
      _attempts = 0;
      _setStatus(RealtimeStatus.connected);
    }

    if (raw is! String) return;
    try {
      final event = RealtimeEvent.parse(raw);
      if (event.type == 'ping') {
        // Ответ на наш пинг: соединение живо, ничего делать не нужно.
        return;
      }
      _events.add(event);
    } catch (_) {
      // Битое событие не должно рвать соединение.
    }
  }

  void _onError(Object channel, Object error) {
    if (!identical(channel, _channel)) return;
    _cleanupSocket();
    _scheduleReconnect();
  }

  void _onClosed(Object channel) {
    if (!identical(channel, _channel)) return;
    _cleanupSocket();
    _scheduleReconnect();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    // Сервер сам шлёт пинг каждые 25 секунд; наш пинг подтверждает,
    // что клиент тоже жив, и обнаруживает «мёртвое» соединение.
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      send({'type': 'ping'});
    });
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _setStatus(RealtimeStatus.disconnected);
    if (_reconnectTimer?.isActive ?? false) return;

    // Сначала пробуем часто, затем отступаем: не долбим сервер, когда он лежит.
    _attempts = (_attempts + 1).clamp(1, 6);
    final delay = Duration(seconds: [1, 2, 4, 8, 15, 30][_attempts - 1]);

    _reconnectTimer = Timer(delay, () {
      final token = tokenProvider.accessToken;
      if (token != null && token.isNotEmpty) {
        connect();
      }
    });
  }

  void _cleanupSocket() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _subscription?.cancel();
    _subscription = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      // close может бросить, если сокет уже мёртв: это не проблема.
      unawaited(
          Future<void>.sync(() => channel.sink.close()).catchError((_) {}));
    }
  }

  void _setStatus(RealtimeStatus value) {
    if (_current == value) return;
    _current = value;
    if (!_status.isClosed) _status.add(value);
  }

  String _webSocketUrl(String token) {
    final base = Uri.parse(baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '${base.path}/api/v1/ws',
      queryParameters: {'token': token},
    ).toString();
  }

  /// Отправляет сообщение на сервер: отметка прочтения, набор текста.
  bool send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) return false;
    try {
      channel.sink.add(jsonEncode(payload));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Отмечает сообщения прочитанными прямо через сокет — быстрее REST-запроса.
  bool markRead(String chatId, int upToSeq) => send({
        'type': 'read',
        'data': {'chat_id': chatId, 'up_to_seq': upToSeq},
      });

  void notifyTyping(String chatId, {bool isTyping = true}) => send({
        'type': 'typing',
        'data': {'chat_id': chatId, 'is_typing': isTyping},
      });

  /// Переподключается после смены пользователя или сервера.
  void reconnect() {
    _cleanupSocket();
    _reconnectTimer?.cancel();
    _attempts = 0;
    _setStatus(RealtimeStatus.disconnected);
    connect();
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _cleanupSocket();
    await _events.close();
    await _status.close();
  }
}
