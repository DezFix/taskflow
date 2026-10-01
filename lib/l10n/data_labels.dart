import 'generated/app_localizations.dart';

/// Переводит названия, которые сервер хранит в базе на русском.
///
/// Ключи системных ролей, названия должностей и меток приходят с
/// сервера по-русски: они лежат в базе, и менять их при смене языка
/// нельзя. Поэтому узнаём их по имени и показываем перевод.
///
/// Свои роли и должности, названные администратором, сюда не
/// попадают: их названия показываются как есть, на любом языке.
abstract final class DataLabels {
  /// Системные роли: идентификатор с сервера -> перевод.
  static String? roleTitle(String? i18nKey, AppLocalizations l10n) {
    if (i18nKey == null) return null;
    return switch (i18nKey) {
      'admin' => l10n.roleAdmin,
      'head' => l10n.roleHead,
      'staff' => l10n.roleStaff,
      _ => null,
    };
  }

  /// Метки, созданные при первом запуске.
  ///
  /// Сопоставление по точному названию: если администратор переименовал
  /// метку, совпадения не будет и покажется его название.
  static String? seededName(String? title, AppLocalizations l10n) {
    if (title == null || title.isEmpty) return null;
    return switch (title) {
      'Срочно' => l10n.labelUrgent,
      'Ждёт ответа' => l10n.labelWaiting,
      'Клиент' => l10n.labelClient,
      'Доработка' => l10n.labelRefinement,
      'Релиз' => l10n.labelRelease,
      'Рефакторинг' => l10n.labelRefactoring,
      _ => null,
    };
  }

  /// Название роли с переводом, если она системная.
  static String roleName(
    String title,
    String? i18nKey,
    AppLocalizations l10n,
  ) {
    return roleTitle(i18nKey, l10n) ?? title;
  }

  /// Название должности или метки с переводом.
  static String seededLabel(String title, AppLocalizations l10n) {
    return seededName(title, l10n) ?? title;
  }
}
