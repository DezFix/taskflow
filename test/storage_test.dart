/// Тесты хранилища: нормализация адреса, серверы, сессия, доверие сертификату.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskflow/data/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Нормализация адреса', () {
    test('голый IP в офисной сети получает http', () {
      expect(
        AppStorage.normalizeServerUrl('192.168.1.50:8080'),
        'http://192.168.1.50:8080',
      );
      expect(
        AppStorage.normalizeServerUrl('10.0.0.5:8080'),
        'http://10.0.0.5:8080',
      );
    });

    test('домен получает https', () {
      expect(
        AppStorage.normalizeServerUrl('taskflow.company.ru'),
        'https://taskflow.company.ru',
      );
    });

    test('localhost считается локальным', () {
      expect(
        AppStorage.normalizeServerUrl('localhost:8080'),
        'http://localhost:8080',
      );
    });

    test('схема из адреса не меняется', () {
      expect(
        AppStorage.normalizeServerUrl('https://taskflow.company.ru'),
        'https://taskflow.company.ru',
      );
      expect(
        AppStorage.normalizeServerUrl('http://192.168.0.1:9000'),
        'http://192.168.0.1:9000',
      );
    });

    test('лишние слеши в конце убираются', () {
      expect(
        AppStorage.normalizeServerUrl('https://taskflow.company.ru//'),
        'https://taskflow.company.ru',
      );
    });

    test('пробелы обрезаются', () {
      expect(
        AppStorage.normalizeServerUrl('  https://a.example.com  '),
        'https://a.example.com',
      );
    });

    test('пустой адрес остаётся пустым', () {
      expect(AppStorage.normalizeServerUrl('  '), '');
    });

    test('адрес 172.16–172.31 считается локальным', () {
      expect(
        AppStorage.normalizeServerUrl('172.20.1.10:8080'),
        'http://172.20.1.10:8080',
      );
      // За пределами диапазона — внешний адрес, значит https.
      expect(
        AppStorage.normalizeServerUrl('172.32.1.10:8080'),
        'https://172.32.1.10:8080',
      );
    });
  });

  group('Адреса серверов', () {
    test('запоминаются и читаются обратно', () async {
      final storage = await AppStorage.create();
      await storage.rememberServer('192.168.1.10:8080', label: 'Офис 1');

      final servers = storage.servers;
      expect(servers.length, 1);
      expect(servers.first.url, 'http://192.168.1.10:8080');
      expect(servers.first.displayLabel, 'Офис 1');
    });

    test('повторный ввод того же адреса не создаёт дубль', () async {
      final storage = await AppStorage.create();
      await storage.rememberServer('192.168.1.10:8080');
      await storage.rememberServer('192.168.1.10:8080');
      expect(storage.servers.length, 1);
    });

    test('одинаковый адрес с разной записью обновляет метку', () async {
      final storage = await AppStorage.create();
      await storage.rememberServer('192.168.1.10:8080', label: 'Старое');
      await storage.rememberServer('192.168.1.10:8080', label: 'Новое');
      expect(storage.servers.length, 1);
      expect(storage.servers.first.label, 'Новое');
    });

    test('без метки показывается сам адрес', () async {
      final storage = await AppStorage.create();
      await storage.rememberServer('https://taskflow.company.ru');
      expect(storage.servers.first.displayLabel, 'https://taskflow.company.ru');
    });

    test('список ограничен пятью адресами', () async {
      final storage = await AppStorage.create();
      for (var i = 0; i < 8; i++) {
        await storage.rememberServer('10.0.0.$i:8080');
      }
      expect(storage.servers.length, 5);
    });

    test('свежий адрес идёт первым', () async {
      final storage = await AppStorage.create();
      await storage.rememberServer('10.0.0.1:8080');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await storage.rememberServer('10.0.0.2:8080');

      expect(storage.servers.first.url, 'http://10.0.0.2:8080');
    });

    test('сервер можно забыть', () async {
      final storage = await AppStorage.create();
      await storage.rememberServer('10.0.0.1:8080');
      await storage.rememberServer('10.0.0.2:8080');

      await storage.forgetServer('http://10.0.0.1:8080');
      expect(storage.servers.length, 1);
      expect(storage.servers.first.url, 'http://10.0.0.2:8080');
    });

    test('активный сервер сохраняется', () async {
      final storage = await AppStorage.create();
      await storage.setActiveServer('10.0.0.5:8080');
      expect(storage.activeServer, 'http://10.0.0.5:8080');
    });
  });

  group('Сессия', () {
    const session = StoredSession(
      serverUrl: 'https://taskflow.company.ru',
      accessToken: 'access',
      refreshToken: 'refresh',
      username: 'ivan',
      fullName: 'Иван Иванов',
    );

    test('сохраняется и читается обратно', () async {
      final storage = await AppStorage.create();
      await storage.saveSession(session);

      final loaded = storage.session;
      expect(loaded, isNotNull);
      expect(loaded!.accessToken, 'access');
      expect(loaded.refreshToken, 'refresh');
      expect(loaded.serverUrl, 'https://taskflow.company.ru');
      expect(loaded.username, 'ivan');
    });

    test('очищается по запросу', () async {
      final storage = await AppStorage.create();
      await storage.saveSession(session);
      await storage.clearSession();
      expect(storage.session, isNull);
    });

    test('последний логин запоминается', () async {
      final storage = await AppStorage.create();
      await storage.setLastUsername('petr');
      expect(storage.lastUsername, 'petr');
    });

    test('clearAll убирает сессию и активный сервер', () async {
      final storage = await AppStorage.create();
      await storage.saveSession(session);
      await storage.setActiveServer('10.0.0.5:8080');

      await storage.clearAll();
      expect(storage.session, isNull);
      expect(storage.activeServer, isNull);
    });
  });

  group('Доверие к сертификату', () {
    test('выдаётся и отзывается для конкретного адреса', () async {
      final storage = await AppStorage.create();
      await storage.trustCertificate('https://10.0.0.5:8443');

      expect(
        storage.trustsCertificate('https://10.0.0.5:8443'),
        isTrue,
      );
      // Соседний сервер остаётся без доверия.
      expect(
        storage.trustsCertificate('https://10.0.0.6:8443'),
        isFalse,
      );

      await storage.untrustCertificate('https://10.0.0.5:8443');
      expect(storage.trustsCertificate('https://10.0.0.5:8443'), isFalse);
    });

    test('сравнение идёт по нормализованному адресу', () async {
      final storage = await AppStorage.create();
      await storage.trustCertificate('10.0.0.5:8443');
      expect(
        storage.trustsCertificate('http://10.0.0.5:8443'),
        isTrue,
      );
    });
  });

  group('ServerEntry', () {
    test('json-разбор и обратная запись', () {
      final entry = ServerEntry.fromJson({
        'url': 'https://a.example.com',
        'label': 'Офис',
        'last_used': '2026-01-01T10:00:00Z',
      });
      expect(entry.url, 'https://a.example.com');
      expect(entry.label, 'Офис');
      expect(entry.lastUsedAt, isNotNull);
      expect(entry.toJson()['url'], 'https://a.example.com');
    });

    test('без даты последнего использования', () {
      final entry = ServerEntry.fromJson({'url': 'https://a.example.com'});
      expect(entry.lastUsedAt, isNull);
      expect(entry.toJson().containsKey('last_used'), isFalse);
    });
  });

  group('Нормализация адреса сервера', () {
    test('адрес без схемы в офисной сети получает http', () {
      expect(AppStorage.normalizeServerUrl('192.168.1.50:8080'),
          'http://192.168.1.50:8080');
      expect(AppStorage.normalizeServerUrl('localhost:8080'),
          'http://localhost:8080');
      expect(AppStorage.normalizeServerUrl('10.0.0.5:8443'),
          'http://10.0.0.5:8443');
    });

    test('публичный адрес без схемы получает https', () {
      expect(AppStorage.normalizeServerUrl('taskflow.example.com'),
          'https://taskflow.example.com');
    });

    test('явная схема сохраняется', () {
      expect(AppStorage.normalizeServerUrl('http://192.168.1.50:8080'),
          'http://192.168.1.50:8080');
      expect(AppStorage.normalizeServerUrl('https://office.example.com'),
          'https://office.example.com');
    });

    test('0.0.0.0 — адрес прослушивания, а не подключения', () {
      // Подключаться к 0.0.0.0 нельзя, поэтому считаем намерением
      // указать локальный компьютер.
      expect(AppStorage.normalizeServerUrl('0.0.0.0:8080'),
          'http://127.0.0.1:8080');
      expect(AppStorage.normalizeServerUrl('0.0.0.0'), 'http://127.0.0.1');
    });

    test('хвостовые слэши убираются', () {
      expect(AppStorage.normalizeServerUrl('http://localhost:8080///'),
          'http://localhost:8080');
    });

    test('схема считается явной только когда её написали', () {
      expect(
          AppStorage.hasExplicitScheme('https://office.example.com'), isTrue);
      expect(AppStorage.hasExplicitScheme('http://192.168.1.5:8080'), isTrue);
      expect(AppStorage.hasExplicitScheme('192.168.1.5:8080'), isFalse);
      expect(AppStorage.hasExplicitScheme('office.example.com'), isFalse);
    });
  });
}
