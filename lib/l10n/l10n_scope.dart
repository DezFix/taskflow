import 'generated/app_localizations.dart';
import 'generated/app_localizations_ru.dart';

/// Текущий язык интерфейса для кода, который живёт вне дерева виджетов.
///
/// Сообщения об ошибках формируются в API-клиенте, где BuildContext
/// недоступен: их читают десятки мест интерфейса, и передавать перевод
/// в каждый вызов непрактично. Поэтому переводы кладём сюда, а
/// MaterialApp обновляет значение при каждой сборке.
abstract final class L10nScope {
  static AppLocalizations? _current;

  /// Переводы текущего языка.
  ///
  /// Без языка (например в тесте до первой сборки) отдаём русский:
  /// он и есть язык по умолчанию, и сообщение остаётся осмысленным.
  static AppLocalizations get current => _current ?? AppLocalizationsRu();

  /// Вызывается из MaterialApp, когда язык интерфейса изменился.
  static void update(AppLocalizations? value) {
    _current = value;
  }
}
