/// Экран входа: логин или email, пароль, обязательная смена пароля.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/storage.dart';
import '../../state/app_state.dart';
import '../theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Последний логин подставляем: сотрудник входит на одном и том же
    // сервере каждый день.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final last = ref.read(storageProvider).lastUsername;
      if (last != null && last.isNotEmpty) {
        _identifierController.text = last;
      }
    });
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref.read(appStageProvider.notifier).login(
            identifier: _identifierController.text,
            password: _passwordController.text,
          );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverUrl = ref.watch(serverUrlProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isLoading
              ? null
              : () => ref.read(appStageProvider.notifier).forgetServer(),
          tooltip: 'Другой сервер',
        ),
        title: const Text('Вход'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (serverUrl.isNotEmpty) _ServerChip(url: serverUrl),
                    const SizedBox(height: Insets.lg),
                    TextFormField(
                      controller: _identifierController,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Логин или email',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) =>
                          (value ?? '').trim().isEmpty ? 'Введите логин' : null,
                    ),
                    const SizedBox(height: Insets.md),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        labelText: 'Пароль',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                          tooltip: _obscure ? 'Показать' : 'Скрыть',
                        ),
                      ),
                      validator: (value) =>
                          (value ?? '').isEmpty ? 'Введите пароль' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Insets.md),
                      _LoginError(message: _error!),
                    ],
                    const SizedBox(height: Insets.lg),
                    FilledButton(
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Войти'),
                    ),
                    const SizedBox(height: Insets.md),
                    TextButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pushReplacementNamed(
                                '/login/password-policy',
                              ),
                      icon: const Icon(Icons.help_outline, size: 18),
                      label: const Text('Не помню пароль'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerChip extends StatelessWidget {
  const _ServerChip({
    required this.url,
  });

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Insets.sm + 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(Insets.radius),
      ),
      child: Row(
        children: [
          const Icon(Icons.dns_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Сервер',
                  style:
                      TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                Text(
                  url,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginError extends StatelessWidget {
  const _LoginError({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Insets.sm + 4),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Insets.radiusSmall),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Экран первоначальной настройки сервера: создаёт администратора.
class ServerSetupWizardScreen extends ConsumerStatefulWidget {
  const ServerSetupWizardScreen({super.key});

  @override
  ConsumerState<ServerSetupWizardScreen> createState() =>
      _ServerSetupWizardScreenState();
}

class _ServerSetupWizardScreenState
    extends ConsumerState<ServerSetupWizardScreen> {
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repeatController = TextEditingController();
  final _organizationController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _passwordController.dispose();
    _repeatController.dispose();
    _organizationController.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Используем общий клиент из провайдера: он уже умеет доверять
    // сертификату, если сотрудник подтвердил его при подключении.
    // Свой клиент здесь потерял бы это настройку.
    final stage = ref.read(appStageProvider.notifier);
    final storage = ref.read(storageProvider);
    final repository = ref.read(authRepositoryProvider);

    try {
      final result = await repository.setup(
        username: _usernameController.text,
        password: _passwordController.text,
        fullName: _fullNameController.text,
        organizationName: _organizationController.text.isEmpty
            ? null
            : _organizationController.text,
      );

      await storage.saveSession(
        StoredSession(
          serverUrl: ref.read(serverUrlProvider),
          accessToken: result.tokens.accessToken,
          refreshToken: result.tokens.refreshToken,
          username: result.user.username,
          fullName: result.user.fullName,
        ),
      );
      await storage.setLastUsername(result.user.username);
      ref.read(sessionProvider.notifier).set(storage.session);
      ref.read(currentUserProvider.notifier).setUser(result.user);
      stage.setStage(AppStage.ready);
      // Реалтайм подключаем сразу: без него чат и задачи не обновляются
      // до перезапуска приложения.
      ref.read(realtimeProvider).reconnect();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройка сервера')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(Insets.md),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(Insets.radius),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppColors.info,
                            size: 20,
                          ),
                          SizedBox(width: Insets.sm),
                          Expanded(
                            child: Text(
                              'Этот сервер ещё не настроен. Создайте учётную '
                              'запись администратора — она же будет первой '
                              'в списке сотрудников.',
                              style: TextStyle(fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Insets.lg),
                    TextFormField(
                      controller: _organizationController,
                      decoration: const InputDecoration(
                        labelText: 'Организация (необязательно)',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                    ),
                    const SizedBox(height: Insets.md),
                    TextFormField(
                      controller: _fullNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Ваше имя и фамилия',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (value) => (value ?? '').trim().length < 2
                          ? 'Введите имя'
                          : null,
                    ),
                    const SizedBox(height: Insets.md),
                    TextFormField(
                      controller: _usernameController,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Логин администратора',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.length < 3) return 'Минимум 3 символа';
                        return null;
                      },
                    ),
                    const SizedBox(height: Insets.md),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Пароль',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: Insets.md),
                    TextFormField(
                      controller: _repeatController,
                      obscureText: _obscure,
                      decoration: const InputDecoration(
                        labelText: 'Повторите пароль',
                        prefixIcon: Icon(Icons.lock_reset_outlined),
                      ),
                      validator: (value) => value != _passwordController.text
                          ? 'Пароли не совпадают'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Insets.md),
                      _LoginError(message: _error!),
                    ],
                    const SizedBox(height: Insets.lg),
                    FilledButton(
                      onPressed: _isLoading ? null : _setup,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Создать администратора'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.length < 8) return 'Минимум 8 символов';
    final hasLetters = password.contains(RegExp(r'[a-zA-Zа-яА-Я]'));
    final hasDigits = password.contains(RegExp(r'\d'));
    if (!hasLetters || !hasDigits) {
      return 'Нужны буквы и цифры';
    }
    return null;
  }
}

/// Заглушка ссылки на экран смены пароля.
class PasswordResetScreen extends ConsumerWidget {
  const PasswordResetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Восстановление доступа')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_person_outlined, size: 48),
                const SizedBox(height: Insets.md),
                const Text(
                  'Обратитесь к главе отдела',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: Insets.sm),
                const Text(
                  'Он сбросит ваш пароль и выдаст временный. После входа '
                  'приложение попросит придумать новый.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.4),
                ),
                const SizedBox(height: Insets.lg),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Вернуться ко входу'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
