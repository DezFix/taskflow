import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// Языки, доступные в интерфейсе.
///
/// Порядок задаёт порядок в переключателе. Русский и украинский идут
/// рядом, потому что это ближайшие языки сотрудников офиса, английский
/// добавлен для чтения документации и внешних подрядчиков.
enum AppLanguage {
  russian('ru', '🇷🇺'),
  ukrainian('uk', '🇺🇦'),
  english('en', '🇬🇧');

  const AppLanguage(this.code, this.flag);

  final String code;
  final String flag;

  static AppLanguage? fromCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final language in values) {
      if (language.code == code) return language;
    }
    return null;
  }
}

/// Подпись языка на том языке, который выбран.
///
/// Так человек узнаёт нужный вариант, даже если ещё не читает
/// названия на этом языке: украинский подписан «Українська».
String languageLabel(AppLanguage language, AppLocalizations l10n) {
  return switch (language) {
    AppLanguage.russian => l10n.languageRussian,
    AppLanguage.ukrainian => l10n.languageUkrainian,
    AppLanguage.english => l10n.languageEnglish,
  };
}

/// Меняет язык интерфейса и запоминает выбор.
class LocaleController {
  LocaleController(this._ref);

  final Ref _ref;

  /// Текущий выбор; null — язык операционной системы.
  AppLanguage? get current =>
      AppLanguage.fromCode(_ref.read(localeCodeProvider));

  Future<void> select(AppLanguage? language) async {
    final code = language?.code;
    _ref.read(localeCodeProvider.notifier).state = code;
    await _ref.read(storageProvider).setLocaleCode(code);
  }

  /// Переключает на следующий язык по кругу — для кнопки в шапке.
  Future<void> cycle() async {
    final languages = AppLanguage.values;
    final current = this.current;
    final next = current == null
        ? languages.first
        : languages[(languages.indexOf(current) + 1) % languages.length];
    await select(next);
  }
}

final localeControllerProvider = Provider<LocaleController>(
  (ref) => LocaleController(ref),
);

/// Кнопка выбора языка.
///
/// Ставится в шапке главных экранов. Компактный вариант [compact]
/// показывает только флаг и подсказку, полный — выпадающий список
/// с названиями языков.
class LanguageSelector extends ConsumerWidget {
  const LanguageSelector({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.watch(localeControllerProvider);
    final current = controller.current;

    if (compact) {
      return IconButton(
        tooltip: l10n.languageTitle,
        onPressed: controller.cycle,
        icon: Text(current?.flag ?? '🌐', style: const TextStyle(fontSize: 20)),
      );
    }

    return PopupMenuButton<AppLanguage?>(
      tooltip: l10n.languageTitle,
      initialValue: current,
      onSelected: controller.select,
      itemBuilder: (context) => [
        _item(l10n, null, '🌐', l10n.languageSystem, current?.code),
        for (final language in AppLanguage.values)
          _item(
            l10n,
            language,
            language.flag,
            languageLabel(language, l10n),
            current?.code,
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(current?.flag ?? '🌐', style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<AppLanguage?> _item(
    AppLocalizations l10n,
    AppLanguage? language,
    String icon,
    String label,
    String? selectedCode,
  ) {
    final selected = selectedCode == language?.code;
    return PopupMenuItem<AppLanguage?>(
      value: language,
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: Insets.sm),
          Expanded(child: Text(label)),
          if (selected) const Icon(Icons.check, size: 18),
        ],
      ),
    );
  }
}
