/// Карточка задачи: описание, комментарии, фотоотчёт, история.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/controllers.dart';
import '../file_picking.dart';
import '../theme.dart';
import '../widgets.dart';

class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(taskDetailProvider(taskId));
    final task = state.task;

    if (task == null) {
      return Scaffold(
        appBar: AppBar(),
        body: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : EmptyState(
                icon: Icons.error_outline,
                title: 'Задача не найдена',
                message: state.error,
                action: FilledButton(
                  onPressed: () =>
                      ref.read(taskDetailProvider(taskId).notifier).load(),
                  child: const Text('Повторить'),
                ),
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Задача'),
        actions: [_TaskMenu(task: task, taskId: taskId)],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(taskDetailProvider(taskId).notifier).load(),
        child: ListView(
          padding: const EdgeInsets.all(Insets.md),
          children: [
            _Title(task: task),
            const SizedBox(height: Insets.md),
            _StatusRow(task: task, taskId: taskId),
            const SizedBox(height: Insets.md),
            if (task.description != null && task.description!.isNotEmpty) ...[
              SectionCard(
                title: 'Описание',
                child: Text(
                  task.description!,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ),
              const SizedBox(height: Insets.md),
            ],
            _DetailsCard(task: task, taskId: taskId),
            const SizedBox(height: Insets.md),
            if (task.tags.isNotEmpty) ...[
              _TagsRow(tags: task.tags),
              const SizedBox(height: Insets.md),
            ],
            if (task.attachments.isNotEmpty) ...[
              _AttachmentsCard(attachments: task.attachments),
              const SizedBox(height: Insets.md),
            ],
            _CommentsSection(task: task, taskId: taskId),
            const SizedBox(height: Insets.md),
            if (task.history.isNotEmpty) ...[
              _HistoryCard(entries: task.history),
              const SizedBox(height: Insets.md),
            ],
          ],
        ),
      ),
      floatingActionButton: _ReportFab(task: task, taskId: taskId),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({
    required this.task,
  });

  final Task task;

  @override
  Widget build(BuildContext context) {
    return Text(
      task.title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
    );
  }
}

/// Смена статуса и приоритета: главное действие на карточке.
class _StatusRow extends ConsumerWidget {
  const _StatusRow({
    required this.task,
    required this.taskId,
  });

  final Task task;
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.can('tasks.edit_any') == true ||
        (user?.can('tasks.edit_assigned') == true &&
            task.assignee?.id == user?.id);

    if (!canEdit) {
      return Row(
        children: [
          StatusBadge(status: task.status),
          const SizedBox(width: Insets.sm),
          PriorityBadge(priority: task.priority),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final status in TaskStatus.values) ...[
            _StatusChip(
              status: status,
              selected: task.status == status,
              onTap: () => _changeStatus(context, ref, status),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    TaskStatus status,
  ) async {
    // Завершение обычно сопровождается пояснением — спрашиваем.
    // null без результата означает, что сотрудник закрыл диалог.
    if (status == TaskStatus.done) {
      final comment = await showInputDialog<String>(
        context,
        title: 'Завершить задачу',
        message: 'Добавьте комментарий: что сделано (необязательно).',
        label: 'Комментарий',
        hint: 'Например, заменил диск, проверил работу',
        confirmText: 'Завершить',
        maxLength: 2000,
      );
      // Диалог без комментария всё равно завершает задачу: возвращаем пустую строку.
      if (comment == null && !context.mounted) return;
      await ref
          .read(taskDetailProvider(taskId).notifier)
          .setStatus(status, comment: (comment ?? '').trim());
      return;
    }
    await ref.read(taskDetailProvider(taskId).notifier).setStatus(status);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final TaskStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.statusColor(status.wire);
    return Material(
      color: selected ? color : color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            status.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailsCard extends ConsumerWidget {
  const _DetailsCard({
    required this.task,
    required this.taskId,
  });

  final Task task;
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canAssign = user?.can('tasks.assign') ?? false;

    return SectionCard(
      title: 'Параметры',
      child: Column(
        children: [
          InfoRow(
            label: 'Исполнитель',
            value: task.assignee?.displayName ?? 'Не назначен',
          ),
          InfoRow(label: 'Автор', value: task.author?.displayName ?? '—'),
          InfoRow(
            label: 'Срок',
            value: Format.dueLabel(task.dueAt, overdue: task.isOverdue),
            valueColor: task.isOverdue ? AppColors.danger : null,
          ),
          InfoRow(
            label: 'Создана',
            value: Format.dateTime(task.createdAt),
          ),
          if (task.completedAt != null)
            InfoRow(
              label: 'Завершена',
              value: Format.dateTime(task.completedAt),
            ),
          if (task.estimatedHours != null)
            InfoRow(
              label: 'Оценка',
              value: '${task.estimatedHours} ч',
            ),
          if (canAssign) ...[
            const SizedBox(height: Insets.sm),
            OutlinedButton.icon(
              onPressed: () => _changeAssignee(context, ref),
              icon: const Icon(Icons.assignment_ind_outlined, size: 18),
              label: const Text('Назначить исполнителя'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _changeAssignee(BuildContext context, WidgetRef ref) async {
    final directory = ref.watch(directoryProvider);
    final users = directory.users.where((u) => u.isActive).toList();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                Insets.md,
                0,
                Insets.md,
                Insets.sm,
              ),
              child: Text(
                'Назначить исполнителя',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Без исполнителя'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await ref.read(taskDetailProvider(taskId).notifier).assign();
              },
            ),
            const Divider(),
            ...users.map(
              (user) => ListTile(
                leading: UserAvatar(user: user),
                title: Text(user.displayName),
                subtitle: Text(user.subtitle),
                trailing: task.assignee?.id == user.id
                    ? const Icon(Icons.check, color: AppColors.success)
                    : null,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await ref
                      .read(taskDetailProvider(taskId).notifier)
                      .assign(assigneeId: user.id);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagsRow extends StatelessWidget {
  const _TagsRow({
    required this.tags,
  });

  final List<TaskTag> tags;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tags
          .map(
            (tag) => Chip(
              label: Text(tag.name),
              visualDensity: VisualDensity.compact,
            ),
          )
          .toList(),
    );
  }
}

class _AttachmentsCard extends StatelessWidget {
  const _AttachmentsCard({
    required this.attachments,
  });

  final List<Attachment> attachments;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Вложения (${attachments.length})',
      child: Column(
        children: attachments
            .map(
              (attachment) => _AttachmentTile(attachment: attachment),
            )
            .toList(),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
  });

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            attachment.isImage
                ? Icons.image_outlined
                : attachment.isAudio
                    ? Icons.audiotrack_outlined
                    : Icons.insert_drive_file_outlined,
            size: 20,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Text(
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            Format.fileSize(attachment.sizeBytes),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentsSection extends ConsumerStatefulWidget {
  const _CommentsSection({
    required this.task,
    required this.taskId,
  });

  final Task task;
  final String taskId;

  @override
  ConsumerState<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<_CommentsSection> {
  final _controller = TextEditingController();
  bool _isWorkReport = false;
  final List<Attachment> _pending = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _pending.isEmpty) return;

    final ok =
        await ref.read(taskDetailProvider(widget.taskId).notifier).addComment(
              body: text.isEmpty ? null : text,
              attachments: _pending,
              isWorkReport: _isWorkReport,
            );

    if (ok) {
      _controller.clear();
      setState(() {
        _pending.clear();
        _isWorkReport = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = [...widget.task.comments]..sort(
        (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
          a.createdAt ?? DateTime(0),
        ),
      );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Комментарии и отчёты',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            if (comments.isNotEmpty)
              Text(
                '${comments.length}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: Insets.sm),
        if (comments.isEmpty)
          Container(
            padding: const EdgeInsets.all(Insets.md),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(Insets.radius),
            ),
            child: const Text(
              'Комментариев пока нет. Здесь сотрудник отчитывается о работе '
              'и прикладывает фотографии.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          )
        else
          ...comments.map(
            (comment) => Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: _CommentCard(comment: comment),
            ),
          ),
        const SizedBox(height: Insets.sm),
        _CommentComposer(
          controller: _controller,
          isWorkReport: _isWorkReport,
          pendingFiles: _pending,
          onToggleWorkReport: () =>
              setState(() => _isWorkReport = !_isWorkReport),
          onAddFiles: _attachFiles,
          onRemoveFile: (index) => setState(() => _pending.removeAt(index)),
          onSend: _send,
        ),
      ],
    );
  }

  Future<void> _attachFiles() async {
    final picked = await pickAndUploadImages(
      context,
      ref,
      taskId: widget.taskId,
    );
    if (picked.isNotEmpty) {
      setState(() => _pending.addAll(picked));
    }
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({
    required this.comment,
  });

  final TaskComment comment;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(user: comment.author, size: 28),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment.author?.displayName ?? 'Сотрудник',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        Format.ago(comment.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (comment.isWorkReport)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.assignment_turned_in,
                          size: 13,
                          color: AppColors.success,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Отчёт',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (comment.body != null) ...[
              const SizedBox(height: Insets.sm),
              Text(comment.body!,
                  style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
            if (comment.attachments.isNotEmpty) ...[
              const SizedBox(height: Insets.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: comment.attachments
                    .map(
                      (attachment) => _AttachmentChip(attachment: attachment),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
  });

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            attachment.isImage ? Icons.image_outlined : Icons.insert_drive_file,
            size: 15,
            color: AppColors.primary,
          ),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            Format.fileSize(attachment.sizeBytes),
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Поле ввода комментария с флажком «отчёт» и выбором файлов.
class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.isWorkReport,
    required this.pendingFiles,
    required this.onToggleWorkReport,
    required this.onAddFiles,
    required this.onRemoveFile,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isWorkReport;
  final List<Attachment> pendingFiles;
  final VoidCallback onToggleWorkReport;
  final VoidCallback onAddFiles;
  final void Function(int index) onRemoveFile;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.sm + 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pendingFiles.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var index = 0; index < pendingFiles.length; index++)
                    InputChip(
                      label: Text(pendingFiles[index].name),
                      onDeleted: () => onRemoveFile(index),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: Insets.sm),
            ],
            TextField(
              controller: controller,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                hintText: 'Комментарий или отчёт о выполненной работе',
                border: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 4),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: onAddFiles,
                  tooltip: 'Приложить фото',
                ),
                Expanded(
                  child: FilterChip(
                    label: const Text('Отчёт о работе'),
                    selected: isWorkReport,
                    onSelected: (_) => onToggleWorkReport(),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: Insets.sm),
                FilledButton(
                  onPressed: onSend,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  child: const Text('Отправить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.entries,
  });

  final List<TaskHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final ordered = [...entries]..sort(
        (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
          a.createdAt ?? DateTime(0),
        ),
      );

    return SectionCard(
      title: 'История изменений',
      child: Column(
        children: ordered
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: Insets.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(top: 5, right: Insets.sm),
                      decoration: BoxDecoration(
                        color: AppColors.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.user?.displayName ?? 'Система'} — '
                            '${entry.fieldTitle.toLowerCase()}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (entry.newValue != null)
                            Text(
                              entry.newValue!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          Text(
                            Format.dateTime(entry.createdAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _TaskMenu extends ConsumerWidget {
  const _TaskMenu({
    required this.task,
    required this.taskId,
  });

  final Task task;
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canDelete = user?.can('tasks.delete') ?? false;

    return PopupMenuButton<String>(
      onSelected: (action) => _handle(context, ref, action),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'refresh',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.refresh),
            title: Text('Обновить'),
          ),
        ),
        if (canDelete)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, color: AppColors.danger),
              title: Text(
                'Удалить задачу',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    if (action == 'refresh') {
      await ref.read(taskDetailProvider(taskId).notifier).load();
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Удалить задачу?',
      message: 'Задача пропадёт из списка, но останется в истории отчётов.',
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(tasksRepositoryProvider).delete(taskId);
      ref.read(taskListProvider.notifier).removeTask(taskId);
      if (context.mounted) Navigator.of(context).pop();
    } catch (error) {
      if (context.mounted) {
        ref.read(appErrorBusProvider).showError(error);
      }
    }
  }
}

class _ReportFab extends ConsumerWidget {
  const _ReportFab({
    required this.task,
    required this.taskId,
  });

  final Task task;
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canReport =
        task.assignee?.id == user?.id || user?.can('tasks.edit_any') == true;

    if (!canReport || task.status == TaskStatus.done) {
      return const SizedBox.shrink();
    }

    return FloatingActionButton.extended(
      onPressed: () async {
        final comment = await showInputDialog<String>(
          context,
          title: 'Отчёт о выполненной работе',
          message: 'Что было сделано? Задача перейдёт на проверку.',
          label: 'Отчёт',
          confirmText: 'Отправить',
          maxLength: 2000,
        );
        if (comment == null) return;
        await ref
            .read(taskDetailProvider(taskId).notifier)
            .addComment(body: comment, isWorkReport: true);
      },
      icon: const Icon(Icons.assignment_turned_in_outlined),
      label: const Text('Отчёт'),
    );
  }
}
