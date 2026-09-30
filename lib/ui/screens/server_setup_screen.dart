/// Экран выбора сервера: сотрудник указывает адрес своего офиса.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../data/storage.dart';
import '../../state/app_state.dart';
import '../theme.dart';

class ServerSetupScreen extends ConsumerStatefulWidget {
  const ServerSetupScreen({super.key});

  @override
  ConsumerState<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends ConsumerState<ServerSetupScreen> {
  final _urlController = TextEditingController();
  final _labelController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isChecking = false;
  bool _trustCertificate = false;
  String? _error;
  ServerInfo? _serverInfo;
  bool _showAdvanced = false;

  @override
  void dispose() {
    _urlController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  /// Проверяет адрес и переходит к входу либо к настройке сервера.
  Future<void> _check() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isChecking = true;
      _error = null;
      _serverInfo = null;
    });

    try {
      final info = await ref.read(appStageProvider.notifier).connectToServer(
            _urlController.text,
            trustCertificate: _trustCertificate,
            label: _labelController.text.isEmpty ? null : _labelController.text,
          );
      if (!mounted) return;
      setState(() {
        _serverInfo = info;
        _isChecking = false;
        // Доверие к сертификату не включаем автоматически: сотрудник
        // должен подтвердить его явно, иначе смена адреса на другой
        // хост тихо отключила бы проверку сертификата.
      });

      if (info.requiresSetup) {
        // Сервер ещё не настроен: сразу открываем мастер.
        Navigator.of(context).pushNamed('/setup');
      } else {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _error = error.message;
        // Ошибка сертификата лечится одним переключателем — сразу его
        // показываем, чтобы сотрудник не искал причину по настройкам.
        if (error.code == 'certificate_error') _trustCertificate = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedServers = ref.watch(savedServersProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Header(),
                    const SizedBox(height: Insets.xl),
                    if (savedServers.isNotEmpty) ...[
                      Text(
                        'Недавние серверы',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary.withValues(alpha: 1),
                        ),
                      ),
                      const SizedBox(height: Insets.sm),
                      ...savedServers.map(
                        (server) => _SavedServerTile(
                          server: server,
                          onTap: _isChecking
                              ? null
                              : () {
                                  _urlController.text = server.url;
                                  _labelController.text = server.label ?? '';
                                  _check();
                                },
                          onRemove: () async {
                            await ref
                                .read(storageProvider)
                                .forgetServer(server.url);
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(height: Insets.lg),
                      const RowDivider(),
                      const SizedBox(height: Insets.lg),
                    ],
                    TextFormField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      textInputAction: TextInputAction.go,
                      onFieldSubmitted: (_) => _check(),
                      decoration: const InputDecoration(
                        labelText: 'Адрес сервера',
                        hintText: '192.168.1.50:8080 или taskflow.company.ru',
                        prefixIcon: Icon(Icons.dns_outlined),
                      ),
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.isEmpty) return 'Введите адрес сервера';
                        if (!text.contains('.') && !text.contains(':')) {
                          return 'Похоже, это не адрес. Пример: 192.168.1.50:8080';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: Insets.sm),
                    _AddressHint(url: _urlController.text),
                    const SizedBox(height: Insets.md),
                    _AdvancedToggle(
                      expanded: _showAdvanced,
                      onToggle: () =>
                          setState(() => _showAdvanced = !_showAdvanced),
                    ),
                    if (_showAdvanced) ...[
                      const SizedBox(height: Insets.md),
                      TextFormField(
                        controller: _labelController,
                        decoration: const InputDecoration(
                          labelText: 'Название сервера',
                          hintText: 'Например, Офис на Пресненской',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: Insets.sm),
                      _CertificateSwitch(
                        value: _trustCertificate,
                        onChanged: (value) =>
                            setState(() => _trustCertificate = value),
                      ),
                    ],
                    if (_serverInfo != null) ...[
                      const SizedBox(height: Insets.md),
                      _ServerInfoCard(info: _serverInfo!),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: Insets.md),
                      _ErrorBanner(
                        message: _error!,
                        showTrustOption:
                            _error!.toLowerCase().contains('сертифик') &&
                                !_showAdvanced,
                        onTrust: () {
                          setState(() {
                            _showAdvanced = true;
                            _trustCertificate = true;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: Insets.lg),
                    FilledButton.icon(
                      onPressed: _isChecking ? null : _check,
                      icon: _isChecking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.arrow_forward),
                      label: Text(
                        _isChecking ? 'Проверяем сервер…' : 'Подключиться',
                      ),
                    ),
                    const SizedBox(height: Insets.md),
                    const _Footer(),
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

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.checklist_rtl, size: 40, color: Colors.white),
        ),
        const SizedBox(height: Insets.md),
        const Text(
          'TaskFlow',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Insets.xs),
        Text(
          'Управление IT-отделом',
          style: TextStyle(
            fontSize: 15,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white70
                : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _SavedServerTile extends StatelessWidget {
  const _SavedServerTile({
    required this.server,
    required this.onTap,
    required this.onRemove,
  });

  final ServerEntry server;
  final VoidCallback? onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Insets.radius),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: Insets.sm + 2,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(Insets.radius),
            ),
            child: Row(
              children: [
                const Icon(Icons.dns_outlined, size: 20),
                const SizedBox(width: Insets.sm + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.displayLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        server.url,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onRemove,
                  tooltip: 'Забыть сервер',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Подсказка по формату адреса: сотрудник часто вводит его вручную.
class _AddressHint extends StatelessWidget {
  const _AddressHint({
    required this.url,
  });

  final String url;

  @override
  Widget build(BuildContext context) {
    final normalized = url.isEmpty ? '' : AppStorage.normalizeServerUrl(url);
    if (!normalized.startsWith('http')) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        Icon(
          normalized.startsWith('https')
              ? Icons.lock_outline
              : Icons.lock_open_outlined,
          size: 14,
          color: normalized.startsWith('https')
              ? AppColors.success
              : AppColors.warning,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            normalized.startsWith('https')
                ? 'Защищённое соединение: $normalized'
                : 'Без шифрования: $normalized. Подходит для доверенной сети офиса.',
            style: TextStyle(
              fontSize: 12,
              color: normalized.startsWith('https')
                  ? AppColors.success
                  : AppColors.warning,
            ),
          ),
        ),
      ],
    );
  }
}

class _AdvancedToggle extends StatelessWidget {
  const _AdvancedToggle({
    required this.expanded,
    required this.onToggle,
  });

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onToggle,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.zero,
      ),
      icon: Icon(
        expanded ? Icons.expand_less : Icons.expand_more,
        size: 18,
      ),
      label: const Text('Дополнительно', style: TextStyle(fontSize: 13)),
    );
  }
}

class _CertificateSwitch extends StatelessWidget {
  const _CertificateSwitch({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Insets.sm + 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Insets.radiusSmall),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            value: value,
            onChanged: onChanged,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'Доверять сертификату сервера',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Для офисной сети и VPN, где сертификат выпущен локально',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerInfoCard extends StatelessWidget {
  const _ServerInfoCard({
    required this.info,
  });

  final ServerInfo info;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 20),
                const SizedBox(width: Insets.sm),
                Text(
                  'Сервер найден: ${info.name} ${info.version}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (info.voiceEnabled) ...[
              const SizedBox(height: Insets.sm),
              Row(
                children: [
                  const Icon(Icons.mic,
                      size: 15, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Распознавание голоса включено, модель ${info.voiceModel}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    this.showTrustOption = false,
    this.onTrust,
  });

  final String message;
  final bool showTrustOption;
  final VoidCallback? onTrust;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Insets.radius),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.danger,
                size: 20,
              ),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
          if (showTrustOption) ...[
            const SizedBox(height: Insets.sm),
            TextButton.icon(
              onPressed: onTrust,
              icon: const Icon(Icons.lock_open, size: 18),
              label: const Text('Разрешить сертификат сервера'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.open_in_new, size: 13, color: AppColors.textMuted),
        const SizedBox(width: 5),
        Text(
          'Открытый исходный код · MIT',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white38
                : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class RowDivider extends StatelessWidget {
  const RowDivider({super.key});

  @override
  Widget build(BuildContext context) => const Divider();
}
