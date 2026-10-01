import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Обязательная смена временного пароля.
///
/// Сервер не пускает в приложение с временным паролем, поэтому экран
/// показывается вместо рабочего пространства. Раньше проверка жила
/// только в профиле: сотрудник мог годами работать с паролем, который
/// администратор передал в открытом чате.
class PasswordChangeScreen extends ConsumerStatefulWidget {
  const PasswordChangeScreen({super.key});

  @override
  ConsumerState<PasswordChangeScreen> createState() =>
      _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends ConsumerState<PasswordChangeScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _repeatController = TextEditingController();
  bool _obscure = true;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _repeatController.dispose();
    super.dispose();
  }

  String? _validateNew(String? value) {
    final l10n = AppLocalizations.of(context);
    final text = value ?? '';
    if (text.length < 8) return l10n.profilePasswordMinLength;
    if (!RegExp(r'[a-zA-Zа-яА-Я]').hasMatch(text)) {
      return l10n.profilePasswordNeedsLetters;
    }
    if (!RegExp(r'\d').hasMatch(text)) return l10n.profilePasswordNeedsDigits;
    return null;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final newError = _validateNew(_newController.text);
    if (newError != null) {
      setState(() => _error = newError);
      return;
    }
    if (_newController.text != _repeatController.text) {
      setState(() => _error = l10n.profilePasswordMismatch);
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
            allDevices: false,
          );
      if (!mounted) return;
      // Обновляем профиль: снимок пользователя приносит must_change_password,
      // после смены пароля он сброшен, и роутер покажет рабочее место.
      await ref.read(currentUserProvider.notifier).load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error =
            error is Exception ? '$error' : l10n.profilePasswordChangeFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileNewPasswordTitle),
        actions: [
          TextButton(
            onPressed: _isSaving
                ? null
                : () => ref.read(appStageProvider.notifier).logout(),
            child: Text(l10n.profileLogoutTitle),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Insets.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.profileMustChangePasswordBanner,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: Insets.md),
                    TextField(
                      controller: _currentController,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: l10n.profileCurrentPasswordTitle,
                      ),
                    ),
                    const SizedBox(height: Insets.md),
                    TextField(
                      controller: _newController,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: l10n.profileNewPasswordTitle,
                      ),
                    ),
                    const SizedBox(height: Insets.md),
                    TextField(
                      controller: _repeatController,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: l10n.profileRepeatPasswordTitle,
                      ),
                    ),
                    const SizedBox(height: Insets.sm),
                    Row(
                      children: [
                        Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          child: Text(l10n.profileShowPassword),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Insets.sm),
                      Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                    const SizedBox(height: Insets.md),
                    FilledButton(
                      onPressed: _isSaving ? null : _submit,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(l10n.profileChangeConfirm),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
