/// Настройки сервера: состояние, параметры распознавания, сведения о системе.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../l10n/generated/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
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
    final l10n = AppLocalizations.of(context);

    return SectionCard(
      title: l10n.settingsConnectionTitle,
      child: Column(
        children: [
          InfoRow(
            label: l10n.settingsAddressLabel,
            value: url,
            monospace: true,
          ),
          InfoRow(
            label: l10n.settingsEncryptionLabel,
            value: url.startsWith('https')
                ? l10n.settingsEncryptionOn
                : l10n.settingsEncryptionOff,
            valueColor:
                url.startsWith('https') ? AppColors.success : AppColors.warning,
          ),
          InfoRow(
            label: l10n.settingsCertTrustLabel,
            value: trusted
                ? l10n.settingsCertTrustAllowed
                : l10n.settingsCertTrustDefault,
          ),
          const SizedBox(height: Insets.sm),
          Text(
            l10n.settingsCertTrustHint,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
    final l10n = AppLocalizations.of(context);

    return SectionCard(
      title: l10n.settingsVoiceTitle,
      child: Column(
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: (value) => _update({'enabled': value}),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsVoiceEnabled),
            subtitle: Text(
              l10n.settingsVoiceSubtitle,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const Divider(),
          DropdownButtonFormField<String>(
            initialValue: models.contains(model) ? model : models.firstOrNull,
            decoration: InputDecoration(labelText: l10n.settingsModelLabel),
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
            decoration: InputDecoration(labelText: l10n.languageTitle),
            items: [
              DropdownMenuItem(
                value: 'ru',
                child: Text(l10n.languageRussian),
              ),
              DropdownMenuItem(
                value: 'en',
                child: Text(l10n.languageEnglish),
              ),
              DropdownMenuItem(
                value: 'uk',
                child: Text(l10n.languageUkrainian),
              ),
              DropdownMenuItem(
                value: 'de',
                child: Text(l10n.languageGerman),
              ),
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
                        SnackBar(
                          content: Text(l10n.settingsVoiceModelLoading),
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
            label: Text(l10n.settingsVoiceModelPreload),
          ),
        ],
      ),
    );
  }

  String _modelTitle(String key) {
    final l10n = AppLocalizations.of(context);
    return switch (key) {
      'tiny' => l10n.settingsModelTiny,
      'base' => l10n.settingsModelBase,
      'small' => l10n.settingsModelSmall,
      'medium' => l10n.settingsModelMedium,
      _ => key,
    };
  }

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
    final l10n = AppLocalizations.of(context);

    return SectionCard(
      title: l10n.settingsSystemTitle,
      child: Column(
        children: [
          InfoRow(label: 'Python', value: Json.text(info['python'], '—')),
          InfoRow(
            label: l10n.settingsPlatformLabel,
            value: Json.text(info['platform'], '—'),
          ),
          InfoRow(
            label: l10n.settingsDatabaseLabel,
            value: Json.text(info['database'], '—'),
          ),
          InfoRow(
            label: l10n.settingsFileLimitLabel,
            value: '${Json.integer(info['max_upload_mb'])} '
                '${l10n.settingsMegabytes}',
          ),
          InfoRow(
            label: l10n.settingsServerTimeLabel,
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
    final l10n = AppLocalizations.of(context);

    return SectionCard(
      title: l10n.settingsAboutTitle,
      child: Column(
        children: [
          InfoRow(label: l10n.settingsAppNameLabel, value: 'TaskFlow'),
          InfoRow(label: l10n.settingsVersionLabel, value: '1.0.0'),
          InfoRow(label: l10n.settingsLicenseLabel, value: 'MIT'),
          const SizedBox(height: Insets.sm),
          Text(
            l10n.settingsAboutNote,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
