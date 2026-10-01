import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/models.dart';
import 'package:taskflow/l10n/data_labels.dart';
import 'package:taskflow/l10n/generated/app_localizations.dart';
import 'package:taskflow/l10n/generated/app_localizations_en.dart';
import 'package:taskflow/l10n/generated/app_localizations_ru.dart';
import 'package:taskflow/l10n/generated/app_localizations_uk.dart';
import 'package:taskflow/l10n/l10n_scope.dart';
import 'package:taskflow/ui/language_selector.dart';

/// Проверяет, что переводы действительно переключаются, а не лежат
/// в коде по-русски.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Языки интерфейса', () {
    test('доступны русский, украинский и английский', () {
      final codes = AppLocalizations.supportedLocales
          .map((locale) => locale.languageCode)
          .toList();
      expect(codes, containsAll(<String>['ru', 'uk', 'en']));
    });

    test('одна и та же надпись переводится в каждом языке', () {
      final ru = AppLocalizationsRu();
      final uk = AppLocalizationsUk();
      final en = AppLocalizationsEn();

      expect(ru.commonSave, 'Сохранить');
      expect(uk.commonSave, 'Зберегти');
      expect(en.commonSave, 'Save');

      expect(ru.tabTasks, 'Задачи');
      expect(uk.tabTasks, 'Задачі');
      expect(en.tabTasks, 'Tasks');
    });

    test('переводы не остаются русскими в украинском и английском', () {
      final uk = AppLocalizationsUk();
      final en = AppLocalizationsEn();

      // Если ключ забыли перевести, gen-l10n подставил бы русский.
      expect(uk.commonCancel, isNot('Отмена'));
      expect(en.commonCancel, isNot('Отмена'));
      expect(uk.loginTitle, isNot('Вход'));
      expect(en.loginTitle, isNot('Вход'));
    });

    test('подстановка параметров работает во всех языках', () {
      final ru = AppLocalizationsRu();
      final uk = AppLocalizationsUk();
      final en = AppLocalizationsEn();

      expect(ru.agoMinutes(5), '5 мин назад');
      expect(uk.agoMinutes(5), '5 хв тому');
      expect(en.agoMinutes(5), '5 min ago');

      expect(en.sizeMegabytes('1.5'), '1.5 MB');
    });

    test('код языка распознаётся, неизвестный игнорируется', () {
      expect(AppLanguage.fromCode('uk'), AppLanguage.ukrainian);
      expect(AppLanguage.fromCode('en'), AppLanguage.english);
      expect(AppLanguage.fromCode('de'), isNull);
      expect(AppLanguage.fromCode(null), isNull);
    });

    test('подпись языка даётся на самом языке', () {
      // Украинский подписан украинским, чтобы его узнали и те,
      // кто ещё не читает этот язык.
      expect(languageLabel(AppLanguage.ukrainian, AppLocalizationsRu()),
          'Украинский');
      expect(
          languageLabel(AppLanguage.russian, AppLocalizationsEn()), 'Russian');
    });
  });

  group('Общий скоуп переводов', () {
    test('до первого вызова MaterialApp отдаёт язык по умолчанию', () {
      L10nScope.update(null);
      expect(L10nScope.current.commonSave, 'Сохранить');
    });

    test('обновляется вместе с языком интерфейса', () {
      L10nScope.update(AppLocalizationsEn());
      expect(L10nScope.current.commonSave, 'Save');
      L10nScope.update(AppLocalizationsUk());
      expect(L10nScope.current.commonSave, 'Зберегти');
      L10nScope.update(null);
    });
  });

  group('Названия из базы', () {
    test('системная роль переводится по идентификатору', () {
      final en = AppLocalizationsEn();
      expect(
        DataLabels.roleName('Администратор', 'admin', en),
        'Administrator',
      );
      expect(
          DataLabels.roleName('Глава отдела', 'head', en), 'Department head');
      expect(DataLabels.roleName('Сотрудник', 'staff', en), 'Staff member');
    });

    test('своя роль остаётся как названа', () {
      // Название задал администратор: переводить его нельзя.
      const custom = 'Наблюдатель дежурной смены';
      for (final l10n in <AppLocalizations>[
        AppLocalizationsRu(),
        AppLocalizationsUk(),
        AppLocalizationsEn(),
      ]) {
        expect(DataLabels.roleName(custom, null, l10n), custom);
      }
    });

    test('базовые должности и метки узнаются по названию', () {
      final en = AppLocalizationsEn();
      expect(
        DataLabels.seededLabel('Системный администратор', en),
        'System administrator',
      );
      expect(DataLabels.seededLabel('Рефакторинг', en), 'Refactoring');
      expect(DataLabels.seededLabel('Джуниор', en), 'Джуниор');
    });

    test('роль из ответа сервера переводится целиком', () {
      final role = Role.fromJson({
        'id': 'r1',
        'key': 'Сотрудник',
        'title': 'Сотрудник',
        'i18n_key': 'staff',
        'permissions': ['tasks.view'],
        'is_system': true,
      });
      expect(role.localizedTitle(AppLocalizationsEn()), 'Staff member');
      expect(role.localizedTitle(AppLocalizationsUk()), 'Співробітник');
    });

    test('у роли без идентификатора перевода нет', () {
      final role = Role.fromJson({
        'id': 'r2',
        'key': 'Наблюдатель',
        'title': 'Наблюдатель',
      });
      expect(role.i18nKey, isNull);
      expect(role.localizedTitle(AppLocalizationsEn()), 'Наблюдатель');
    });
  });
}
