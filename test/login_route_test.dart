import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskflow/data/storage.dart';
import 'package:taskflow/l10n/generated/app_localizations.dart';
import 'package:taskflow/state/app_state.dart';
import 'package:taskflow/ui/screens/login_screen.dart';

/// Экземпляр AppStageNotifier с заранее заданным состоянием.
///
/// Конструктор родителя при создании читает сохранённую сессию и ходит
/// в сеть, а в тесте нужен конкретный этап. Поэтому состояние
/// подменяется геттером.
class _FakeStageNotifier extends AppStageNotifier {
  _FakeStageNotifier(super.ref, this._stage);

  final AppStage _stage;

  @override
  AppStage get state => _stage;
}

/// Обёртка, кладёт LoginScreen поверх маршрута-подложки.
///
/// Именно так выглядит проблема: экран входа открыт именованным
/// маршрутом /login поверх home, а не как содержимое home.
Widget _appUnderTest(AppStage stage, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      serverUrlProvider.overrideWith((ref) => 'http://localhost:8080'),
      appStageProvider.overrideWith((ref) => _FakeStageNotifier(ref, stage)),
      storageProvider.overrideWith((ref) => AppStorage(prefs)),
    ],
    child: MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const Scaffold(body: Text('workspace')),
      routes: {'/login': (_) => const LoginScreen()},
      initialRoute: '/login',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('при активной сессии экран входа закрывается', (tester) async {
    await tester.pumpWidget(_appUnderTest(AppStage.ready, prefs));
    await tester.pumpAndSettle();

    // Подложка с рабочим пространством должна быть видна вместо формы.
    expect(find.text('workspace'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('без сессии экран входа остаётся', (tester) async {
    await tester.pumpWidget(_appUnderTest(AppStage.needsLogin, prefs));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('workspace'), findsNothing);
  });
}
