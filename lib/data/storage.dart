/// Хранилище адреса сервера, токенов и настроек клиента.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Один сохранённый сервер. Приложение умеет работать с несколькими
/// офисами: адреса переключаются без переустановки.
class ServerEntry {
  const ServerEntry({
    required this.url,
    this.label,
    this.lastUsedAt,
  });

  final String url;
  final String? label;
  final DateTime? lastUsedAt;

  /// Имя для списка: то, что ввёл сотрудник, либо адрес.
  String get displayLabel {
    final text = label?.trim();
    if (text != null && text.isNotEmpty) return text;
    return url;
  }

  ServerEntry copyWith({String? label, DateTime? lastUsedAt}) => ServerEntry(
        url: url,
        label: label ?? this.label,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        if (label != null) 'label': label,
        if (lastUsedAt != null) 'last_used': lastUsedAt!.toIso8601String(),
      };

  factory ServerEntry.fromJson(Map<String, dynamic> json) => ServerEntry(
        url: json['url']?.toString() ?? '',
        label: json['label']?.toString(),
        lastUsedAt: json['last_used'] == null
            ? null
            : DateTime.tryParse(json['last_used'].toString()),
      );
}

/// Данные, которые нужно сохранять между запусками.
class StoredSession {
  const StoredSession({
    required this.serverUrl,
    required this.accessToken,
    required this.refreshToken,
    this.username,
    this.fullName,
  });

  final String serverUrl;
  final String accessToken;
  final String refreshToken;
  final String? username;
  final String? fullName;

  Map<String, dynamic> toJson() => {
        'server_url': serverUrl,
        'access_token': accessToken,
        'refresh_token': refreshToken,
        if (username != null) 'username': username,
        if (fullName != null) 'full_name': fullName,
      };

  factory StoredSession.fromJson(Map<String, dynamic> json) => StoredSession(
        serverUrl: json['server_url']?.toString() ?? '',
        accessToken: json['access_token']?.toString() ?? '',
        refreshToken: json['refresh_token']?.toString() ?? '',
        username: json['username']?.toString(),
        fullName: json['full_name']?.toString(),
      );
}

/// Обёртка над SharedPreferences с понятными именами ключей.
class AppStorage {
  AppStorage(this._prefs);

  static const _serversKey = 'taskflow.servers';
  static const _activeServerKey = 'taskflow.active_server';
  static const _sessionKey = 'taskflow.session';
  static const _trustCertificatesKey = 'taskflow.trust_certificates';
  static const _lastUsernameKey = 'taskflow.last_username';
  static const _localeKey = 'taskflow.locale';

  final SharedPreferences _prefs;

  static Future<AppStorage> create() async =>
      AppStorage(await SharedPreferences.getInstance());

  // --- Адреса серверов ---

  List<ServerEntry> get servers {
    final raw = _prefs.getString(_serversKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final entries = <ServerEntry>[];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final entry = ServerEntry.fromJson(item);
          if (entry.url.isNotEmpty) entries.add(entry);
        }
      }
      // Свежие адреса — вверху: список открывают чаще всего последний.
      entries.sort(
        (a, b) => (b.lastUsedAt ?? DateTime(0)).compareTo(
          a.lastUsedAt ?? DateTime(0),
        ),
      );
      return entries;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveServers(List<ServerEntry> entries) async {
    await _prefs.setString(
      _serversKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  /// Добавляет адрес в список или обновляет метку существующего.
  Future<ServerEntry> rememberServer(String url, {String? label}) async {
    final normalized = normalizeServerUrl(url);
    final existing = servers.toList();
    final index = existing.indexWhere((e) => e.url == normalized);

    if (index >= 0) {
      final updated = existing[index].copyWith(
        label: label,
        lastUsedAt: DateTime.now(),
      );
      existing[index] = updated;
      await saveServers(existing);
      return updated;
    }

    final entry = ServerEntry(
      url: normalized,
      label: label,
      lastUsedAt: DateTime.now(),
    );
    existing.insert(0, entry);
    // Больше пяти адресов не нужно: список быстро засоряется опечатками.
    if (existing.length > 5) {
      existing.removeRange(5, existing.length);
    }
    await saveServers(existing);
    return entry;
  }

  Future<void> forgetServer(String url) async {
    final remaining = servers.where((e) => e.url != url).toList();
    await saveServers(remaining);
    if (activeServer == url) {
      await _prefs.remove(_activeServerKey);
    }
  }

  String? get activeServer => _prefs.getString(_activeServerKey);

  Future<void> setActiveServer(String url) async {
    await _prefs.setString(_activeServerKey, normalizeServerUrl(url));
  }

  // --- Сессия ---

  StoredSession? get session {
    final raw = _prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return StoredSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(StoredSession session) async {
    await _prefs.setString(_sessionKey, jsonEncode(session.toJson()));
  }

  Future<void> clearSession() async {
    await _prefs.remove(_sessionKey);
  }

  String? get lastUsername => _prefs.getString(_lastUsernameKey);

  Future<void> setLastUsername(String username) async {
    await _prefs.setString(_lastUsernameKey, username);
  }

  // --- Доверие к сертификату ---

  /// Разрешить самоподписанный сертификат для конкретного сервера.
  /// Нужно для офисной сети и VPN, где сертификат выпущен локально.
  Set<String> get trustedCertificates {
    final raw = _prefs.getString(_trustCertificatesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Set<String>.from(jsonDecode(raw) as List<dynamic>);
    } catch (_) {
      return {};
    }
  }

  Future<void> trustCertificate(String url) async {
    final trusted = trustedCertificates..add(_certKey(url));
    await _prefs.setString(
      _trustCertificatesKey,
      jsonEncode(trusted.toList()),
    );
  }

  Future<void> untrustCertificate(String url) async {
    final trusted = trustedCertificates..remove(_certKey(url));
    await _prefs.setString(
      _trustCertificatesKey,
      jsonEncode(trusted.toList()),
    );
  }

  /// Проверяет, доверяем ли мы сертификату этого сервера.
  ///
  /// Ключ — только хост и порт: сотрудник подтверждал доверие именно
  /// этому хосту, и смена http на https не должна его отменять.
  bool trustsCertificate(String url) =>
      trustedCertificates.contains(_certKey(url));

  /// Ключ доверия: только хост и порт, без схемы и пути.
  ///
  /// Сотрудник подтверждал доверие именно этому адресу. Если бы в ключ
  /// входила схема, переход с http на https молча возвращал бы
  /// проверку сертификата к недоверенному состоянию.
  static String _certKey(String url) {
    final normalized = normalizeServerUrl(url);
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) return normalized.toLowerCase();
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.host.toLowerCase()}$port';
  }

  // --- Язык интерфейса ---

  /// Выбранный язык: 'ru', 'uk', 'en' или null, когда система решает сама.
  String? get localeCode => _prefs.getString(_localeKey);

  /// Сохраняет выбор языка. Пустое значение означает «как в системе».
  Future<void> setLocaleCode(String? code) async {
    if (code == null || code.isEmpty) {
      await _prefs.remove(_localeKey);
      return;
    }
    await _prefs.setString(_localeKey, code);
  }

  Future<void> clearAll() async {
    await _prefs.remove(_sessionKey);
    await _prefs.remove(_activeServerKey);
  }

  /// Приводит адрес к виду `https://host:port` без слеша в конце.
  ///
  /// Сотрудник вводит `192.168.1.50:8080` — это самый частый случай,
  /// поэтому схему и путь добавляем сами.
  static String normalizeServerUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return url;

    // Схема по умолчанию: голый IP в офисной сети обычно без TLS.
    if (!url.contains('://')) {
      final isLocal = url.startsWith('192.168.') ||
          url.startsWith('10.') ||
          url.startsWith('127.') ||
          url.startsWith('localhost') ||
          url.startsWith('[::1]') ||
          RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(url);
      url = '${isLocal ? 'http' : 'https'}://$url';
    }

    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
}
