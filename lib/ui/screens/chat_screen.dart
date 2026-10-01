/// Экран чата: сообщения, вложения, голосовые с распознаванием.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/controllers.dart';
import '../file_picking.dart';
import '../theme.dart';
import '../voice_recorder.dart';
import '../widgets.dart';
import 'chat_bubbles.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chatId, this.initialTitle});

  final String chatId;
  final String? initialTitle;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _recorder = VoiceRecorder();

  VoiceRecordingState _recording = VoiceRecordingState.idle;
  Duration _recordingTime = Duration.zero;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatListProvider.notifier).clearUnread(widget.chatId);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _inputController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Вверху списка подгружаем более старые сообщения.
    if (_scrollController.position.pixels <= 120) {
      ref.read(messagesProvider(widget.chatId).notifier).loadMore();
    }
  }

  Future<void> _scrollToBottom() async {
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();
    setState(() => _sending = true);

    final ok =
        await ref.read(messagesProvider(widget.chatId).notifier).sendText(text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) _scrollToBottom();
  }

  // --- Голосовые ---

  Future<void> _startRecording() async {
    setState(() => _error = null);
    final started = await _recorder.start();
    if (!mounted) return;

    if (!started) {
      setState(() {
        _error = AppLocalizations.of(context).chatMicPermissionError;
      });
      return;
    }

    setState(() {
      _recording = _recorder.state;
      _recordingTime = Duration.zero;
    });

    // Счётчик и автоостановка по лимиту длительности.
    _timer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _recordingTime = _recorder.elapsed);
      if (_recorder.reachedLimit) {
        timer.cancel();
        await _stopAndSend();
      }
    });
  }

  Timer? _timer;

  Future<void> _stopAndSend() async {
    _timer?.cancel();
    final capture = await _recorder.stop();
    if (!mounted) return;

    setState(() {
      _recording = VoiceRecordingState.idle;
      _recordingTime = Duration.zero;
    });

    if (capture == null) {
      setState(() {
        _error = AppLocalizations.of(context).chatVoiceRecordError;
      });
      return;
    }

    setState(() => _sending = true);
    final ok =
        await ref.read(messagesProvider(widget.chatId).notifier).sendVoice(
              bytes: capture.bytes,
              filename: 'voice.m4a',
              durationSec: capture.duration.inMilliseconds / 1000,
            );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _scrollToBottom();
    }
  }

  Future<void> _cancelRecording() async {
    _timer?.cancel();
    await _recorder.cancel();
    if (!mounted) return;
    setState(() {
      _recording = VoiceRecordingState.idle;
      _recordingTime = Duration.zero;
    });
  }

  Future<void> _attachFile() async {
    final picked = await pickFiles(context);
    if (picked == null || picked.isEmpty || !mounted) return;

    setState(() => _sending = true);
    try {
      final repository = ref.read(chatRepositoryProvider);
      final message = await repository.sendFile(
        widget.chatId,
        file: UploadFile(
          name: picked.first.name,
          bytes: picked.first.bytes,
          mimeType: mimeTypeFor(picked.first.name),
        ),
        body: picked.length > 1
            ? '${AppLocalizations.of(context).chatFilesAttached}: '
                '${picked.length}'
            : null,
      );
      if (!mounted) return;
      ref.read(messagesProvider(widget.chatId).notifier).confirmSent(message);
      _scrollToBottom();
    } on ApiException catch (error) {
      ref.read(appErrorBusProvider).show(error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(messagesProvider(widget.chatId));
    final myId = ref.watch(currentUserProvider)?.id;
    final messages = state.ordered.reversed.toList();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialTitle ?? l10n.chatTitleFallback,
          style: const TextStyle(fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showChatInfo(context),
            tooltip: l10n.chatInfoTooltip,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildMessageList(context, state, messages, myId),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Insets.sm),
              color: AppColors.danger.withValues(alpha: 0.1),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: AppColors.danger),
              ),
            ),
          ChatComposer(
            controller: _inputController,
            isRecording: _recording == VoiceRecordingState.recording,
            recordingTime: _recordingTime,
            isSending: _sending,
            onSend: _send,
            onAttach: _attachFile,
            onRecord: _startRecording,
            onStopRecord: _stopAndSend,
            onCancelRecord: _cancelRecording,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(
    BuildContext context,
    MessagesState state,
    List<ChatMessage> messages,
    String? myId,
  ) {
    final l10n = AppLocalizations.of(context);

    if (state.isLoading && messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && messages.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off,
        title: l10n.chatLoadErrorTitle,
        message: state.error,
        action: FilledButton(
          onPressed: () =>
              ref.read(messagesProvider(widget.chatId).notifier).load(),
          child: Text(l10n.commonRetry),
        ),
      );
    }

    if (messages.isEmpty) {
      return EmptyState(
        icon: Icons.chat_bubble_outline,
        title: l10n.chatEmptyTitle,
        message: l10n.chatEmptyMessage,
      );
    }

    // Список перевёрнут: новые сообщения снизу, как в мессенджерах.
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.sm,
        vertical: Insets.sm,
      ),
      itemCount: messages.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return const Padding(
            padding: EdgeInsets.all(Insets.sm),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final message = messages[index];
        final previous =
            index + 1 < messages.length ? messages[index + 1] : null;
        // Скрываем аватар и время у подряд идущих сообщений одного автора.
        final grouped = previous != null &&
            previous.sender?.id == message.sender?.id &&
            message.createdAt != null &&
            previous.createdAt != null &&
            message.createdAt!.difference(previous.createdAt!).inMinutes < 3;

        return MessageBubble(
          message: message,
          isMine: message.sender?.id == myId,
          grouped: grouped,
          onRetry: message.status == 'failed' && !message.isVoice
              ? () => _retry(message)
              : null,
        );
      },
    );
  }

  Future<void> _retry(ChatMessage message) async {
    if (message.isVoice) return;
    await ref
        .read(messagesProvider(widget.chatId).notifier)
        .sendText(message.body ?? '');
  }

  Future<void> _showChatInfo(BuildContext context) async {
    final repository = ref.read(chatRepositoryProvider);
    final l10n = AppLocalizations.of(context);
    try {
      final chat = await repository.chat(widget.chatId);
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.md,
                  0,
                  Insets.md,
                  Insets.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat.displayTitle(l10n),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      chat.isGroup
                          ? '${l10n.chatInfoGroupMembers}: '
                              '${chat.members.length}'
                          : l10n.chatInfoDirect,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ...chat.members.map(
                (member) => ListTile(
                  leading: UserAvatar(user: member, size: 36),
                  title: Text(member.displayName),
                  subtitle: Text(member.subtitle),
                ),
              ),
            ],
          ),
        ),
      );
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}
