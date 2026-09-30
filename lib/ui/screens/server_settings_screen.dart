/// Настройки сервера: состояние, параметры распознавания, сведения о системе.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

class ServerSettingsScreen extends ConsumerStatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  ConsumerState<ServerSettingsScreen> createState() =>
      _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends ConsumerState<ServerSettingsScreen> {
  Map<String, dynamic>? _voice;
  Map<String, dynamic>? _system;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final repository = ref.read(reportsRepositoryProvider);
    try {
      final voice = await repository.voiceSettings();
      final system = await repository.systemInfo();
      if (!mounted) return;
      setState(() {
        _voice = voice;
        _system = system;
        _isLoading = false;
      });
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
      appBar: AppBar(title: const Text('Настройки сервера')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(Insets.md),
                children: [
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(Insets.md),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(Insets.radius),
                      ),
                      child: Text(_error!),
                    ),
                  _ConnectionCard(),
                  const SizedBox(height: Insets.md),
                  if (_voice != null) ...[
                    _VoiceCard(
                      settings: _voice!,
                      onChanged: _load,
                    ),
                    const SizedBox(height: Insets.md),
                  ],
                  if (_system != null) ...[
                    _SystemCard(info: _system!),
                    const SizedBox(height: Insets.md),
                  ],
                  const _AboutCard(),
                ],
              ),
            ),
    );
  }
}

class _ConnectionCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(serverUrlProvider);
    final storage = ref.read(storageProvider);
    final trusted = storage.trustsCertificate(url);

    return SectionCard(
      title: 'Подключение',
      child: Column(
        children: [
          InfoRow(label: 'Адрес', value: url, monospace: true),
          InfoRow(
            label: 'Шифрование',
            value: url.startsWith('https')
                ? 'Включено (HTTPS)'
                : 'Нет (HTTP, доверенная сеть)',
            valueColor:
                url.startsWith('https') ? AppColors.success : AppColors.warning,
          ),
          InfoRow(
            label: 'Доверие к сертификату',
            value: trusted ? 'Разрешено' : 'Обычная проверка',
          ),
          const SizedBox(height: Insets.sm),
          const Text(
            'Если сервер доступен по VPN или в локальной сети с '
            'самоподписанным сертификатом, доверие можно включить при входе.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _VoiceCard extends ConsumerStatefulWidget {
  const _VoiceCard({
    required this.settings,
    required this.onChanged,
  });

  final Map<String, dynamic> settings;
  final Future<void> Function() onChanged;

  @override
  ConsumerState<_VoiceCard> createState() => _VoiceCardState();
}

class _VoiceCardState extends ConsumerState<_VoiceCard> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final enabled = Json.flag(settings['enabled']);
    final model = Json.text(settings['model'], 'base');
    final language = Json.text(settings['language'], 'ru');
    final models = Json.strings(settings['available_models']);

    return SectionCard(
      title: 'Распознавание голоса',
      child: Column(
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: (value) => _update({'enabled': value}),
            contentPadding: EdgeInsets.zero,
            title: const Text('Включено'),
            subtitle: const Text(
              'Голосовые расшифровываются на сервере, данные никуда не уходят',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const Divider(),
          DropdownButtonFormField<String>(
            initialValue: models.contains(model) ? model : models.firstOrNull,
            decoration: const InputDecoration(labelText: 'Модель'),
            items: models
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text('${_modelTitle(item)} · $item'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) _update({'model': value});
            },
          ),
          const SizedBox(height: Insets.md),
          DropdownButtonFormField<String>(
            initialValue: language,
            decoration: const InputDecoration(labelText: 'Язык'),
            items: const [
              DropdownMenuItem(value: 'ru', child: Text('Русский')),
              DropdownMenuItem(value: 'en', child: Text('Английский')),
              DropdownMenuItem(value: 'uk', child: Text('Украинский')),
              DropdownMenuItem(value: 'de', child: Text('Немецкий')),
            ],
            onChanged: (value) {
              if (value != null) _update({'language': value});
            },
          ),
          const SizedBox(height: Insets.md),
          OutlinedButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      // Именно warmup, а не запись настроек: сервер
                      // скачивает веса модели в фоне.
                      await ref
                          .read(reportsRepositoryProvider)
                          .warmUpVoiceModel();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Модель загружается, это займёт время'),
                        ),
                      );
                      if (mounted) await widget.onChanged();
                    } on ApiException catch (error) {
                      if (mounted) {
                        ref.read(appErrorBusProvider).show(error.message);
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Загрузить модель заранее'),
          ),
        ],
      ),
    );
  }

  String _modelTitle(String key) => switch (key) {
        'tiny' => 'Быстрая, черновик',
        'base' => 'Баланс (по умолчанию)',
        'small' => 'Точнее',
        'medium' => 'Максимум точности',
        _ => key,
      };

  Future<void> _update(Map<String, dynamic> changes) async {
    setState(() => _saving = true);
    try {
      await ref.read(reportsRepositoryProvider).updateVoiceSettings(changes);
      await widget.onChanged();
    } catch (error) {
      if (mounted) ref.read(appErrorBusProvider).showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SystemCard extends StatelessWidget {
  const _SystemCard({
    required this.info,
  });

  final Map<String, dynamic> info;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Система',
      child: Column(
        children: [
          InfoRow(label: 'Python', value: Json.text(info['python'], '—')),
          InfoRow(label: 'Платформа', value: Json.text(info['platform'], '—')),
          InfoRow(
              label: 'База данных', value: Json.text(info['database'], '—')),
          InfoRow(
            label: 'Лимит файла',
            value: '${Json.integer(info['max_upload_mb'])} МБ',
          ),
          InfoRow(
            label: 'Время сервера',
            value: Json.text(info['server_time'], '—'),
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'О приложении',
      child: Column(
        children: [
          InfoRow(label: 'Название', value: 'TaskFlow'),
          InfoRow(label: 'Версия', value: '1.0.0'),
          InfoRow(label: 'Лицензия', value: 'MIT'),
          const SizedBox(height: Insets.sm),
          const Text(
            'Открытый исходный код. Приложение можно развернуть в своём '
            'офисе на своём сервере.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
