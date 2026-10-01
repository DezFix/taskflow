/// Оформление TaskFlow: цвета, тема, единые стили.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/generated/app_localizations.dart';

/// Палитра приложения. Спокойные синие тона: интерфейс открыт весь день.
class AppColors {
  const AppColors._();

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryLight = Color(0xFF60A5FA);

  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = Color(0xFF0891B2);

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);

  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderStrong = Color(0xFFCBD5E1);

  /// Цвет статуса задачи: цветной кружок в списках.
  static Color statusColor(String status) => switch (status) {
        'new' => info,
        'in_progress' => primary,
        'review' => warning,
        'done' => success,
        'cancelled' => textMuted,
        _ => textMuted,
      };

  /// Цвет приоритета.
  static Color priorityColor(String priority) => switch (priority) {
        'low' => textMuted,
        'normal' => info,
        'high' => warning,
        'urgent' => danger,
        _ => info,
      };

  /// Цвет для первых букв аватара: стабильный для сотрудника.
  static Color avatar(String id) {
    const palette = [
      Color(0xFF2563EB),
      Color(0xFF7C3AED),
      Color(0xFF0891B2),
      Color(0xFF059669),
      Color(0xFFD97706),
      Color(0xFFDB2777),
      Color(0xFF4F46E5),
    ];
    if (id.isEmpty) return palette.first;
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return palette[hash % palette.length];
  }
}

/// Тема приложения для светлого и тёмного режима.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0F172A) : AppColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF1E293B) : AppColors.surface,
        foregroundColor: isDark ? Colors.white : AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF1E293B) : AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isDark ? const Color(0xFF334155) : AppColors.border,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1E293B) : AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF334155) : AppColors.border,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF334155) : AppColors.border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : AppColors.border,
        ),
        labelStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF334155) : AppColors.border,
        space: 1,
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 13,
          color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF1E293B) : AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
    );
  }
}

/// Общие отступы и радиусы: единый ритм на всех экранах.
class Insets {
  const Insets._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  static const double radius = 12;
  static const double radiusSmall = 8;
}

/// Форматирование дат и чисел по-русски.
/// Форматирование дат, времени и размеров файлов.
///
/// Названия месяцев и дней недели берутся из intl: они зависят от
/// локали, и свои списки в коде быстро расходятся с языком устройства.
/// Связки вроде «сегодня» приходят из переводов интерфейса.
class Format {
  const Format._();

  /// Локаль для дат.
  ///
  /// Берём из объекта переводов, а не из контекста: у
  /// AppLocalizations есть собственное имя локали, и так формат
  /// работает даже там, где контекста нет (тесты, фоновые задачи).
  static String _localeName(AppLocalizations l10n) => l10n.localeName;

  /// «5 дек», «сегодня», «вчера», «5 дек 2024».
  static String date(DateTime? value, AppLocalizations l10n) {
    if (value == null) return '—';
    final now = DateTime.now();
    final local = value.toLocal();
    final diff = _daysBetween(local, now);

    if (diff == 0) return l10n.dateShortToday;
    if (diff == 1) return l10n.dateShortYesterday;
    if (diff == -1) return l10n.dateShortTomorrow;

    return DateFormat.MMMd(_localeName(l10n)).format(local) +
        (local.year == now.year ? '' : ' ${local.year}');
  }

  /// «5 дек, 14:30».
  static String dateTime(DateTime? value, AppLocalizations l10n) {
    if (value == null) return '—';
    final local = value.toLocal();
    return '${date(value, l10n)}, ${time(local)}';
  }

  /// «14:30». Формат 24 часа одинаков для всех трёх языков.
  static String time(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// «5 грудня 2024, 14:30» — для подробных подписей.
  static String longDateTime(DateTime? value, AppLocalizations l10n) {
    if (value == null) return '—';
    final local = value.toLocal();
    final day = DateFormat.yMMMMd(_localeName(l10n)).format(local);
    return '$day, ${time(local)}';
  }

  /// Срок задачи: «Сьогодні, 14:30» плюс «прострочено».
  static String dueLabel(
    DateTime? due,
    AppLocalizations l10n, {
    bool overdue = false,
  }) {
    if (due == null) return l10n.dateNoDue;
    final local = due.toLocal();
    final diff = _daysBetween(local, DateTime.now());
    final stamp = time(local);

    final String base;
    if (diff == 0) {
      base = l10n.dateToday(stamp);
    } else if (diff == 1) {
      base = l10n.dateTomorrow(stamp);
    } else if (diff == -1) {
      base = l10n.dateYesterday(stamp);
    } else {
      base = '${date(due, l10n)}, $stamp';
    }
    return overdue ? l10n.dateOverdue(base) : base;
  }

  /// «1:05» — длительность голосового. Формат одинаков для всех языков.
  static String duration(double? seconds) {
    if (seconds == null || seconds <= 0) return '0:00';
    final total = seconds.round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  /// «1.2 MB», «340 KB».
  static String fileSize(int bytes, AppLocalizations l10n) {
    if (bytes < 1024) return l10n.sizeBytes(bytes);
    if (bytes < 1024 * 1024) {
      return l10n.sizeKilobytes((bytes / 1024).toStringAsFixed(0));
    }
    return l10n.sizeMegabytes(
      (bytes / (1024 * 1024)).toStringAsFixed(1),
    );
  }

  /// «Зараз», «5 хв тому», «вчора о 14:30».
  static String ago(DateTime? value, AppLocalizations l10n) {
    if (value == null) return '';
    final local = value.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inSeconds < 60) return l10n.agoNow;
    if (diff.inMinutes < 60) return l10n.agoMinutes(diff.inMinutes);
    if (diff.inHours < 24) return l10n.agoHours(diff.inHours);
    if (diff.inDays == 1) return l10n.agoYesterday(time(local));
    if (diff.inDays < 7) return l10n.agoDays(diff.inDays);
    return date(value, l10n);
  }

  /// Целые дни между двумя датами: положительное число — в прошлом.
  static int _daysBetween(DateTime value, DateTime reference) {
    final a = DateTime(value.year, value.month, value.day);
    final b = DateTime(reference.year, reference.month, reference.day);
    return b.difference(a).inDays;
  }
}
