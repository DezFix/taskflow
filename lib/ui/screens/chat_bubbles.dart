/// Виджеты экрана чата: пузырь сообщения и поле ввода.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../theme.dart';
import '../voice_recorder.dart';
import '../widgets.dart';

/// Пузырь одного сообщения.
class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.grouped = false,
    this.onRetry,
  });

  final ChatMessage message;
  final bool isMine;
  final bool grouped;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    final bubbleColor = message.isDeleted
        ? scheme.surfaceContainerHighest
        : isMine
            ? scheme.primary
            : scheme.surface;

    final textColor = message.isDeleted
        ? AppColors.textMuted
        : isMine
            ? Colors.white
            // Цвет берём из темы, а не константу: тёмно-синий AppColors
            // нечитаем на тёмном фоне, и чужие сообщения пропадали.
            : scheme.onSurface;

    return Padding(
      padding: EdgeInsets.only(top: grouped ? 2 : Insets.sm),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine && !grouped)
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 2),
              child: UserAvatar(user: message.sender, size: 28),
            )
          else if (!isMine)
            const SizedBox(width: 34),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              child: Column(
                crossAxisAlignment:
                    isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!grouped && !isMine)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 3),
                      child: Text(
                        message.sender?.displayName ?? '',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(14),
                        topRight: const Radius.circular(14),
                        bottomLeft: Radius.circular(isMine ? 14 : 4),
                        bottomRight: Radius.circular(isMine ? 4 : 14),
                      ),
                      border:
                          isMine ? null : Border.all(color: AppColors.border),
                    ),
                    child: BubbleContent(
                      message: message,
                      textColor: textColor,
                      isMine: isMine,
                    ),
                  ),
                  if (!message.isDeleted)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                      child: MessageMeta(
                        message: message,
                        isMine: isMine,
                        onRetry: onRetry,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Содержимое пузыря: текст, фото, файл или голосовое.
class BubbleContent extends StatelessWidget {
  const BubbleContent({
    super.key,
    required this.message,
    required this.textColor,
    required this.isMine,
  });

  final ChatMessage message;
  final Color textColor;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (message.isDeleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            l10n.chatMessageDeleted,
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: textColor,
            ),
          ),
        ],
      );
    }

    if (message.isVoice) {
      return VoiceBubble(message: message, isMine: isMine);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.isImage && message.attachment != null)
          ImagePreview(attachment: message.attachment!, isMine: isMine),
        if (message.isFile && message.attachment != null) ...[
          FileRow(
            attachment: message.attachment!,
            textColor: textColor,
          ),
          if (message.body != null && message.body!.isNotEmpty)
            const SizedBox(height: 6),
        ],
        if (message.body != null && message.body!.isNotEmpty)
          Text(
            message.body!,
            style: TextStyle(fontSize: 14, height: 1.4, color: textColor),
          ),
      ],
    );
  }
}

/// Голосовое сообщение: плеер, расшифровка и возможность правки.
class VoiceBubble extends ConsumerWidget {
  const VoiceBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transcript = message.transcript;
    // Цвет из темы, а не константа: тёмно-синий AppColors на
    // тёмном фоне расшифровки нечитался.
    final scheme = Theme.of(context).colorScheme;
    final text = message.transcriptText ?? transcript?.text;
    final pending = transcript?.isPending ?? false;
    final accent = isMine ? Colors.white : AppColors.primary;
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.play_circle_fill, size: 32, color: accent),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(
                  Format.duration(
                    message.voiceDurationSec ?? transcript?.durationSec,
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: isMine ? Colors.white70 : AppColors.textSecondary,
                  ),
                ),
              ),
              if (pending)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                ),
            ],
          ),
          if (text != null && text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.15)
                    : AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  // Цвет из темы: у чужих сообщений тёмный фон, и
                  // тёмно-синий текст на нём не читался.
                  color: isMine ? Colors.white : scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  transcript?.isManual == true
                      ? Icons.edit
                      : Icons.auto_awesome,
                  size: 11,
                  color: isMine ? Colors.white60 : AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  transcript?.isManual == true
                      ? l10n.chatTranscriptManual
                      : l10n.chatTranscriptServer,
                  style: TextStyle(
                    fontSize: 10,
                    color: isMine ? Colors.white60 : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ] else if (transcript?.hasError ?? false) ...[
            const SizedBox(height: 6),
            Text(
              transcript?.status == 'skipped'
                  ? l10n.chatTranscriptDisabled
                  : l10n.chatTranscriptFailed,
              style: TextStyle(
                fontSize: 12,
                color: isMine ? Colors.white70 : AppColors.textMuted,
              ),
            ),
          ] else if (pending) ...[
            const SizedBox(height: 6),
            Text(
              l10n.chatTranscriptPending,
              style: TextStyle(
                fontSize: 12,
                color: isMine ? Colors.white70 : AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ImagePreview extends StatelessWidget {
  const ImagePreview({
    super.key,
    required this.attachment,
    required this.isMine,
  });

  final Attachment attachment;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final url = attachment.previewUrl ?? attachment.url;
    if (url == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240, maxWidth: 240),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 120,
              color: AppColors.border,
              child: const Icon(Icons.broken_image_outlined),
            ),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                height: 120,
                color: AppColors.border,
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.attachment,
    required this.textColor,
  });

  final Attachment attachment;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.insert_drive_file_outlined, size: 20, color: textColor),
        const SizedBox(width: 6),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
              Text(
                Format.fileSize(attachment.sizeBytes, l10n),
                style: TextStyle(
                  fontSize: 11,
                  color: textColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Время, статус доставки и меню сообщения.
class MessageMeta extends StatelessWidget {
  const MessageMeta({
    super.key,
    required this.message,
    required this.isMine,
    this.onRetry,
  });

  final ChatMessage message;
  final bool isMine;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.textMuted;
    final l10n = AppLocalizations.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.status == 'sending')
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(Icons.schedule, size: 11, color: color),
          )
        else if (message.status == 'failed')
          InkWell(
            onTap: onRetry,
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 12,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 3),
                Text(
                  l10n.chatMessageNotSent,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.danger,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          )
        else if (isMine && message.showsStatus)
          Icon(
            message.isRead ? Icons.done_all : Icons.done,
            size: 13,
            color: message.isRead ? AppColors.primary : color,
          ),
        if (message.isEdited) ...[
          const SizedBox(width: 3),
          Text(
            l10n.chatMessageEdited,
            style: TextStyle(fontSize: 9, color: color),
          ),
        ],
        const SizedBox(width: 5),
        Text(
          Format.time(message.createdAt ?? DateTime.now()),
          style: TextStyle(fontSize: 10, color: color),
        ),
      ],
    );
  }
}

/// Поле ввода: текст, вложение, запись голосового.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.isRecording,
    required this.recordingTime,
    required this.isSending,
    required this.onSend,
    required this.onAttach,
    required this.onRecord,
    required this.onStopRecord,
    required this.onCancelRecord,
  });

  final TextEditingController controller;
  final bool isRecording;
  final Duration recordingTime;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onRecord;
  final VoidCallback onStopRecord;
  final VoidCallback onCancelRecord;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    if (isRecording) {
      return RecordingBar(
        elapsed: recordingTime,
        onCancel: onCancelRecord,
        onStop: onStopRecord,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Insets.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file),
                onPressed: isSending ? null : onAttach,
                tooltip: l10n.chatAttachTooltip,
              ),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: l10n.chatInputHint,
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Insets.sm),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  return IconButton.filled(
                    icon: hasText
                        ? const Icon(Icons.send, size: 20)
                        : const Icon(Icons.mic, size: 20),
                    onPressed: isSending
                        ? null
                        : hasText
                            ? onSend
                            : onRecord,
                    tooltip:
                        hasText ? l10n.chatSendTooltip : l10n.chatVoiceSend,
                    style: IconButton.styleFrom(
                      backgroundColor:
                          hasText ? AppColors.primary : AppColors.success,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Панель записи: таймер, отмена и отправка.
class RecordingBar extends StatelessWidget {
  const RecordingBar({
    super.key,
    required this.elapsed,
    required this.onCancel,
    required this.onStop,
  });

  final Duration elapsed;
  final VoidCallback onCancel;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final remaining = kMaxVoiceLength - elapsed;
    final nearLimit = remaining.inSeconds < 30;
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        border: Border(
            top: BorderSide(color: AppColors.danger.withValues(alpha: 0.3))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Insets.sm),
          child: Row(
            children: [
              const PulsingDot(),
              const SizedBox(width: Insets.sm),
              Text(
                formatRecordingTime(elapsed),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(
                  nearLimit
                      ? '${l10n.chatRecordingRemaining} '
                          '${remaining.inSeconds} ${l10n.chatRecordingSecondsUnit}'
                      : l10n.chatRecordingInProgress,
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        nearLimit ? AppColors.danger : AppColors.textSecondary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: onCancel,
                tooltip: l10n.chatRecordingCancelTooltip,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: Insets.xs),
              IconButton.filled(
                icon: const Icon(Icons.send, size: 20),
                onPressed: onStop,
                tooltip: l10n.chatSendTooltip,
                style: IconButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Мигающая точка индикатора записи.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(
              alpha: 0.5 + _controller.value * 0.5,
            ),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
