/// Профиль сотрудника, настройки сервера и смена пароля.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final serverUrl = ref.watch(serverUrlProvider);

    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(Insets.md),
      children: [
        Center(
          child: Column(
            children: [
              UserAvatar(user: user, size: 84),
              const SizedBox(height: Insets.sm + 2),
              Text(
                user.displayName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                user.position?.title ?? user.subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              if (user.roles.isNotEmpty) ...[
                const SizedBox(height: Insets.sm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: user.roles
                      .map((role) => Chip(
                            label: Text(role.title),
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Insets.lg),
        if (user.mustChangePassword)
          _MustChangeBanner(onTap: () => _changePassword(context, ref)),
        SectionCard(
          title: 'Данные',
          child: Column(
            children: [
              InfoRow(label: 'Логин', value: '@${user.username}'),
              if (user.email != null)
                InfoRow(label: 'Email', value: user.email!),
              if (user.phone != null)
                InfoRow(label: 'Телефон', value: user.phone!),
              if (user.lastLoginAt != null)
                InfoRow(
                  label: 'Последний вход',
                  value: Format.longDateTime(user.lastLoginAt),
                ),
              if (user.createdAt != null)
                InfoRow(
                  label: 'В системе с',
                  value: Format.date(user.createdAt),
                ),
            ],
          ),
        ),
        const SizedBox(height: Insets.md),
        SectionCard(
          title: 'Действия',
          child: Column(
            children: [
              _ActionRow(
                icon: Icons.badge_outlined,
                title: 'Изменить профиль',
                onTap: () => _editProfile(context, ref),
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.lock_outline,
                title: 'Сменить пароль',
                onTap: () => _changePassword(context, ref),
              ),
              const Divider(height: 1),
              if (user.can('settings.view'))
                _ActionRow(
                  icon: Icons.tune,
                  title: 'Настройки сервера',
                  onTap: () => Navigator.of(context).pushNamed('/settings'),
                ),
            ],
          ),
        ),
        const SizedBox(height: Insets.md),
        SectionCard(
          title: 'Подключение',
          child: Column(
            children: [
              InfoRow(label: 'Сервер', value: serverUrl, monospace: true),
              const SizedBox(height: Insets.sm),
              _ConnectionRow(url: serverUrl),
            ],
          ),
        ),
        const SizedBox(height: Insets.md),
        OutlinedButton.icon(
          onPressed: () => _logout(context, ref),
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Выйти из аккаунта'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: const BorderSide(color: AppColors.danger),
          ),
        ),
        const SizedBox(height: Insets.md),
        TextButton.icon(
          onPressed: () => _changeServer(context, ref),
          icon: const Icon(Icons.dns_outlined, size: 18),
          label: const Text('Подключиться к другому серверу'),
        ),
        const SizedBox(height: Insets.md),
        Center(
          child: Text(
            'TaskFlow 1.0.0 · MIT',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white38
                  : AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider)!;
    final name = await showInputDialog<String>(
      context,
      title: 'Изменить профиль',
      label: 'Имя и фамилия',
      initialValue: user.fullName,
    );
    if (name == null || !context.mounted) return;

    final phone = await showInputDialog<String>(
      context,
      title: 'Телефон',
      label: 'Номер телефона',
      initialValue: user.phone ?? '',
      keyboardType: TextInputType.phone,
    );
    if (phone == null || !context.mounted) return;

    try {
      await ref
          .read(currentUserProvider.notifier)
          .updateProfile({'full_name': name.trim(), 'phone': phone.trim()});
    } catch (error) {
      if (context.mounted) ref.read(appErrorBusProvider).showError(error);
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final current = await showInputDialog<String>(
      context,
      title: 'Текущий пароль',
      label: 'Пароль',
      obscureText: true,
      confirmText: 'Далее',
    );
    // null означает, что сотрудник закрыл диалог: продолжать нечего.
    if (current == null || !context.mounted) return;

    final next = await showInputDialog<String>(
      context,
      title: 'Новый пароль',
      message: 'Минимум 8 символов, буквы и цифры.',
      label: 'Новый пароль',
      obscureText: true,
      confirmText: 'Далее',
      validator: (value) {
        final text = value ?? '';
        if (text.length < 8) return 'Минимум 8 символов';
        if (!RegExp(r'[a-zA-Zа-яА-Я]').hasMatch(text)) return 'Нужны буквы';
        if (!RegExp(r'\d').hasMatch(text)) return 'Нужны цифры';
        return null;
      },
    );
    if (next == null || !context.mounted) return;

    final repeat = await showInputDialog<String>(
      context,
      title: 'Повторите пароль',
      label: 'Новый пароль ещё раз',
      obscureText: true,
      confirmText: 'Сменить',
      validator: (value) => value != next ? 'Пароли не совпадают' : null,
    );
    if (repeat == null || !context.mounted) return;

    final signOutOthers = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Завершить другие сессии?'),
        content: const Text(
          'Рекомендуется включить, если пароль мог увидеть кто-то ещё.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Да, завершить'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;

    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: current,
            newPassword: next,
            allDevices: signOutOthers ?? false,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Пароль изменён')));
        ref.read(currentUserProvider.notifier).load();
      }
    } catch (error) {
      if (context.mounted) ref.read(appErrorBusProvider).showError(error);
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Выйти из аккаунта?',
      message: 'Адрес сервера сохранится, вход будет выполнен паролем.',
      confirmText: 'Выйти',
      destructive: false,
    );
    if (confirmed) {
      await ref.read(appStageProvider.notifier).logout();
    }
  }

  Future<void> _changeServer(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Сменить сервер?',
      message: 'Текущий сервер будет забыт. Убедитесь, что знаете пароль.',
      confirmText: 'Сменить',
    );
    if (confirmed) {
      await ref.read(appStageProvider.notifier).forgetServer();
    }
  }
}

class _MustChangeBanner extends StatelessWidget {
  const _MustChangeBanner({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Insets.md),
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Insets.radius),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          const SizedBox(width: Insets.sm + 2),
          const Expanded(
            child: Text(
              'Вам выдан временный пароль. Смените его, чтобы защитить учётную запись.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
          TextButton(onPressed: onTap, child: const Text('Сменить')),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
      dense: true,
    );
  }
}

/// Индикатор связи с сервером и переподключение.
class _ConnectionRow extends ConsumerWidget {
  const _ConnectionRow({
    required this.url,
  });

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(realtimeStatusProvider).value;

    final connected = status?.name == 'connected';
    final label = switch (status?.name) {
      'connected' => 'Подключено, обновления в реальном времени',
      'connecting' => 'Подключение…',
      _ => 'Нет связи, идёт переподключение',
    };

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: connected ? AppColors.success : AppColors.warning,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: Insets.sm),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        if (!connected)
          TextButton(
            onPressed: () => ref.read(realtimeProvider).reconnect(),
            child: const Text('Повторить'),
          ),
      ],
    );
  }
}
