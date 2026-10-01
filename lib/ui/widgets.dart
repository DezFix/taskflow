/// Общие виджеты: аватар, пустые состояния, карточки, индикаторы.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../l10n/generated/app_localizations.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// Кэш файлов в памяти: аватары и фото не должны качаться заново
/// при каждом перестроении списка.
final Map<String, Uint8List> _imageCache = <String, Uint8List>{};

/// Изображение с авторизацией.
///
/// Файлы на сервере закрыты: обычный Image.network не умеет слать
/// заголовок с токеном, а в браузере заголовки запрещены вовсе.
/// Поэтому байты забирает dio через [ApiClient.getBytes], который
/// умеет и обновить протухший токен, и повторить запрос.
class AuthenticatedImage extends ConsumerStatefulWidget {
  const AuthenticatedImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  /// Относительный путь вида `/api/v1/files/{id}/download`.
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;

  @override
  ConsumerState<AuthenticatedImage> createState() => _AuthenticatedImageState();
}

class _AuthenticatedImageState extends ConsumerState<AuthenticatedImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AuthenticatedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final path = widget.path;
    final cached = _imageCache[path];
    if (cached != null) {
      if (mounted) setState(() => _bytes = cached);
      return;
    }

    try {
      final bytes = await ref.read(apiClientProvider).getBytes(path);
      if (!mounted || widget.path != path) return;
      _imageCache[path] = bytes;
      setState(() => _bytes = bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width;
    final height = widget.height;
    final bytes = _bytes;

    Widget content;
    if (bytes != null) {
      content = Image.memory(
        bytes,
        width: width,
        height: height,
        fit: widget.fit,
        gaplessPlayback: true,
      );
    } else {
      content = widget.placeholder ?? _fallback();
    }

    if (!_failed) return content;

    // Файл недоступен: показываем заглушку, но не ломаем разметку.
    return widget.placeholder ?? _fallback();
  }

  Widget _fallback() => Container(
        width: widget.width,
        height: widget.height,
        color: AppColors.border,
        child: Icon(
          _failed ? Icons.broken_image_outlined : Icons.image_outlined,
          size: 18,
          color: AppColors.textMuted,
        ),
      );
}

/// Аватар сотрудника или группы. При наличии файла показывает фото,
/// иначе — кружок с инициалами.
class UserAvatar extends ConsumerWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.size = 40,
    this.showPresence = false,
    this.isOnline = false,
  });

  final UserBrief? user;
  final double size;
  final bool showPresence;
  final bool isOnline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (user == null) {
      return _circle(Colors.grey, '?', size);
    }

    final avatarPath = user!.avatarUrl;
    if (avatarPath != null && avatarPath.isNotEmpty) {
      return ClipOval(
        child: AuthenticatedImage(
          path: avatarPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: _circle(
            AppColors.avatar(user!.id),
            user!.initials,
            size,
          ),
        ),
      );
    }

    final widget = _circle(
      AppColors.avatar(user!.id),
      user!.initials,
      size,
    );
    if (!showPresence) return widget;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: BoxDecoration(
              color: isOnline ? AppColors.success : AppColors.textMuted,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).scaffoldBackgroundColor,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _circle(Color color, String initials, double size) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

/// Цветная метка статуса задачи.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.compact = false});

  final TaskStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = AppColors.statusColor(status.wire);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.title(l10n),
        style: TextStyle(
          color: color,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Метка приоритета: для срочных — с точкой, иначе текст.
class PriorityBadge extends StatelessWidget {
  const PriorityBadge(
      {super.key, required this.priority, this.showLow = false});

  final TaskPriority priority;
  final bool showLow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Низкий приоритет — обычное дело, не печатаем его под задачей.
    if (priority == TaskPriority.low && !showLow) {
      return const SizedBox.shrink();
    }

    final color = AppColors.priorityColor(priority.wire);
    if (priority == TaskPriority.urgent) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          // Срочный приоритет показываем заглавными: он должен бросаться
          // в глаза даже мелким шрифтом.
          l10n.priorityUrgent.toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          priority.title(l10n),
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Счётчик непрочитанных сообщений.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    // Больше 99 показываем как «99+»: иначе бейдж растягивает список.
    final text = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Пустое состояние с подсказкой, что делать дальше.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: AppColors.primary),
            ),
            const SizedBox(height: Insets.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            if (message != null) ...[
              const SizedBox(height: Insets.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: Insets.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Карточка с заголовком и содержимым.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.md),
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: Insets.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Плитка показателя для экрана отчётов.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppColors.primary,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Insets.radius),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 17, color: color),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: Insets.sm),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Индикатор связи с сервером: показывает, работает ли реалтайм.
class RealtimeIndicator extends StatelessWidget {
  const RealtimeIndicator(
      {super.key, required this.connected, required this.label});

  final bool connected;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = connected ? AppColors.success : AppColors.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color),
        ),
      ],
    );
  }
}

/// Диалог с полем ввода по центру экрана.
Future<T?> showInputDialog<T>(
  BuildContext context, {
  required String title,
  String? message,
  String? label,
  String? hint,

  /// Подпись кнопки. null — берётся «Сохранить» на языке интерфейса.
  String? confirmText,
  String? initialValue,
  TextInputType? keyboardType,
  TextCapitalization textCapitalization = TextCapitalization.sentences,
  int? maxLength,
  bool obscureText = false,
  String? Function(String?)? validator,
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) => _InputDialog<T>(
      title: title,
      message: message,
      label: label,
      hint: hint,
      confirmText: confirmText ?? AppLocalizations.of(context).commonSave,
      initialValue: initialValue,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLength: maxLength,
      obscureText: obscureText,
      validator: validator,
    ),
  );
}

class _InputDialog<T> extends StatefulWidget {
  const _InputDialog({
    required this.title,
    this.message,
    this.label,
    this.hint,
    this.confirmText,
    this.initialValue,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.sentences,
    this.maxLength,
    this.obscureText = false,
    this.validator,
  });

  final String title;
  final String? message;
  final String? label;
  final String? hint;
  final String? confirmText;
  final String? initialValue;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? maxLength;
  final bool obscureText;
  final String? Function(String?)? validator;

  @override
  State<_InputDialog<T>> createState() => _InputDialogState<T>();
}

class _InputDialogState<T> extends State<_InputDialog<T>> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text;
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(value as T?);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) ...[
            Text(
              widget.message!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: Insets.md),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            textCapitalization: widget.textCapitalization,
            maxLength: widget.maxLength,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              errorText: _error,
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context).commonCancel),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
          child: Text(
            widget.confirmText ?? AppLocalizations.of(context).commonSave,
          ),
        ),
      ],
    );
  }
}

/// Диалог подтверждения опасного действия.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,

  /// null — берётся «Удалить» на языке интерфейса.
  String? confirmText,
  bool destructive = true,
}) async {
  final l10n = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(AppLocalizations.of(dialogContext).commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  minimumSize: const Size(100, 40),
                )
              : FilledButton.styleFrom(minimumSize: const Size(100, 40)),
          child: Text(confirmText ?? l10n.commonDelete),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Плитка «подключено/нет» для настроек сервера.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.monospace = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor ?? AppColors.textPrimary,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
