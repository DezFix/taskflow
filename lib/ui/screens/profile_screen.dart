/// Профиль сотрудника, настройки сервера и смена пароля.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final serverUrl = ref.watch(serverUrlProvider);
    final l10n = AppLocalizations.of(context);

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
                            label: Text(role.localizedTitle(l10n)),
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
          title: l10n.profileSectionDetails,
          child: Column(
            children: [
              InfoRow(
                  label: l10n.profileLoginLabel, value: '@${user.username}'),
              if (user.email != null)
                InfoRow(label: 'Email', value: user.email!),
              if (user.phone != null)
                InfoRow(label: l10n.profilePhoneLabel, value: user.phone!),
              if (user.lastLoginAt != null)
                InfoRow(
                  label: l10n.profileLastLoginLabel,
                  value: Format.longDateTime(user.lastLoginAt, l10n),
                ),
              if (user.createdAt != null)
                InfoRow(
                  label: l10n.profileMemberSinceLabel,
                  value: Format.date(user.createdAt, l10n),
                ),
            ],
          ),
        ),
        const SizedBox(height: Insets.md),
        SectionCard(
          title: l10n.profileSectionActions,
          child: Column(
            children: [
              _ActionRow(
                icon: Icons.badge_outlined,
                title: l10n.profileEditProfile,
                onTap: () => _editProfile(context, ref),
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.lock_outline,
                title: l10n.profileChangePassword,
                onTap: () => _changePassword(context, ref),
              ),
              const Divider(height: 1),
              if (user.can('settings.view'))
                _ActionRow(
                  icon: Icons.tune,
                  title: l10n.profileServerSettings,
                  onTap: () => Navigator.of(context).pushNamed('/settings'),
                ),
            ],
          ),
        ),
        const SizedBox(height: Insets.md),
        SectionCard(
          title: l10n.profileSectionConnection,
          child: Column(
            children: [
              InfoRow(
                label: l10n.profileServerLabel,
                value: serverUrl,
                monospace: true,
              ),
              const SizedBox(height: Insets.sm),
              _ConnectionRow(url: serverUrl),
            ],
          ),
        ),
        const SizedBox(height: Insets.md),
        OutlinedButton.icon(
          onPressed: () => _logout(context, ref),
          icon: const Icon(Icons.logout, size: 18),
          label: Text(l10n.profileLogout),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: const BorderSide(color: AppColors.danger),
          ),
        ),
        const SizedBox(height: Insets.md),
        TextButton.icon(
          onPressed: () => _changeServer(context, ref),
          icon: const Icon(Icons.dns_outlined, size: 18),
          label: Text(l10n.profileConnectOtherServer),
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
    final l10n = AppLocalizations.of(context);
    final user = ref.read(currentUserProvider)!;
    final name = await showInputDialog<String>(
      context,
      title: l10n.profileEditProfile,
      label: l10n.profileFullNameLabel,
      initialValue: user.fullName,
    );
    if (name == null || !context.mounted) return;

    final phone = await showInputDialog<String>(
      context,
      title: l10n.profilePhoneLabel,
      label: l10n.profilePhoneNumberLabel,
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
    final l10n = AppLocalizations.of(context);
    final current = await showInputDialog<String>(
      context,
      title: l10n.profileCurrentPasswordTitle,
      label: l10n.profilePasswordLabel,
      obscureText: true,
      confirmText: l10n.commonNext,
    );
    // null означает, что сотрудник закрыл диалог: продолжать нечего.
    if (current == null || !context.mounted) return;

    final next = await showInputDialog<String>(
      context,
      title: l10n.profileNewPasswordTitle,
      message: l10n.profileNewPasswordHint,
      label: l10n.profileNewPasswordTitle,
      obscureText: true,
      confirmText: l10n.commonNext,
      validator: (value) {
        final text = value ?? '';
        if (text.length < 8) return l10n.profilePasswordMinLength;
        if (!RegExp(r'[a-zA-Zа-яА-Я]').hasMatch(text)) {
          return l10n.profilePasswordNeedsLetters;
        }
        if (!RegExp(r'\d').hasMatch(text)) {
          return l10n.profilePasswordNeedsDigits;
        }
        return null;
      },
    );
    if (next == null || !context.mounted) return;

    final repeat = await showInputDialog<String>(
      context,
      title: l10n.profileRepeatPasswordTitle,
      label: l10n.profileRepeatPasswordLabel,
      obscureText: true,
      confirmText: l10n.profileChangeConfirm,
      validator: (value) => value != next ? l10n.profilePasswordMismatch : null,
    );
    if (repeat == null || !context.mounted) return;

    final signOutOthers = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.profileEndOtherSessionsTitle),
        content: Text(l10n.profileEndOtherSessionsMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.profileEndSessionsConfirm),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.profilePasswordChanged)),
        );
        ref.read(currentUserProvider.notifier).load();
      }
    } catch (error) {
      if (context.mounted) ref.read(appErrorBusProvider).showError(error);
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmDialog(
      context,
      title: l10n.profileLogoutTitle,
      message: l10n.profileLogoutMessage,
      confirmText: l10n.profileLogoutConfirm,
      destructive: false,
    );
    if (confirmed) {
      await ref.read(appStageProvider.notifier).logout();
    }
  }

  Future<void> _changeServer(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmDialog(
      context,
      title: l10n.profileChangeServerTitle,
      message: l10n.profileChangeServerMessage,
      confirmText: l10n.profileChangeConfirm,
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
    final l10n = AppLocalizations.of(context);
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
          Expanded(
            child: Text(
              l10n.profileMustChangePasswordBanner,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
          TextButton(onPressed: onTap, child: Text(l10n.profileChangeConfirm)),
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
    final l10n = AppLocalizations.of(context);

    final connected = status?.name == 'connected';
    final label = switch (status?.name) {
      'connected' => l10n.profileStatusConnected,
      'connecting' => l10n.profileStatusConnecting,
      _ => l10n.profileStatusDisconnected,
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
            child: Text(l10n.commonRetry),
          ),
      ],
    );
  }
}
