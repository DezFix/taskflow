/// Точка входа TaskFlow: маршрутизация, тема, обработка ошибок.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/storage.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/l10n_scope.dart';
import 'state/app_state.dart';
import 'ui/screens/chat_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/server_settings_screen.dart';
import 'ui/screens/server_setup_screen.dart';
import 'ui/screens/workspace_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // intl берёт названия месяцев и дней недели из своих данных, а они
  // загружаются отдельно. Без этого Format.date упадёт на первом же
  // экране со списком задач.
  await initializeDateFormatting();

  // Хранилище создаём после инициализации: язык может прийти оттуда.
  final storage = await AppStorage.create();

  runApp(
    ProviderScope(
      overrides: [storageProvider.overrideWithValue(storage)],
      child: const TaskFlowApp(),
    ),
  );
}

class TaskFlowApp extends ConsumerStatefulWidget {
  const TaskFlowApp({super.key});

  @override
  ConsumerState<TaskFlowApp> createState() => _TaskFlowAppState();
}

class _TaskFlowAppState extends ConsumerState<TaskFlowApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<String>? _errorSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Ошибки из слоя данных показываем плашкой, а не в логах.
      _errorSubscription =
          ref.read(appErrorBusProvider).messages.listen(_showError);
    });
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    super.dispose();
  }

  void _showError(String message) {
    final messenger = _navigatorKey.currentContext;
    if (messenger == null) return;
    ScaffoldMessenger.of(messenger)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final localeCode = ref.watch(localeCodeProvider);

    return MaterialApp(
      title: 'TaskFlow',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      // Переводы: русский, украинский, английский. Пустой код —
      // когда сотрудник не выбрал язык и мы берём системный.
      locale: _localeFor(localeCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      onGenerateRoute: _onGenerateRoute,
      // Ошибки формируются вне дерева виджетов, поэтому переводы
      // кладём в общий скоуп: иначе каждое сообщение было бы русским.
      builder: (context, child) {
        L10nScope.update(AppLocalizations.of(context));
        return child ?? const SizedBox.shrink();
      },
      home: const _StageRouter(),
    );
  }

  /// Разбирает сохранённый код языка в Locale.
  ///
  /// Неизвестное значение игнорируем: лучше язык по умолчанию, чем
  /// падение при старте из-за испорченных настроек.
  static Locale? _localeFor(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final locale in AppLocalizations.supportedLocales) {
      if (locale.languageCode == code) return locale;
    }
    return null;
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/setup':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ServerSetupWizardScreen(),
        );
      case '/login':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const LoginScreen(),
        );
      case '/login/password-policy':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const PasswordResetScreen(),
        );
      case '/settings':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ServerSettingsScreen(),
        );
      case '/chat':
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ChatScreen(
            chatId: args?['chatId'] as String? ?? '',
            initialTitle: args?['title'] as String?,
          ),
        );
      default:
        return null;
    }
  }
}

/// Переключает экраны по этапу приложения.
class _StageRouter extends ConsumerWidget {
  const _StageRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = ref.watch(appStageProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: switch (stage) {
        AppStage.loading => const SplashScreen(),
        AppStage.needsServer => const ServerSetupScreen(),
        AppStage.needsLogin || AppStage.needsSetup => const LoginScreen(),
        AppStage.ready => const WorkspaceShell(),
      },
    );
  }
}
