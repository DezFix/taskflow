/// Карточка задачи в списке: заголовок, статус, срок, исполнитель.
library;

import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';

import '../../data/models.dart';
import '../theme.dart';
import '../widgets.dart';

class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    this.onTap,
    this.showAssignee = true,
  });

  final Task task;
  final VoidCallback? onTap;
  final bool showAssignee;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final done = task.status == TaskStatus.done;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Insets.md),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Цветная полоса статуса: состояние видно без чтения текста.
            Container(
              width: 3,
              height: 36,
              margin: const EdgeInsets.only(right: Insets.sm + 2, top: 2),
              decoration: BoxDecoration(
                color: AppColors.statusColor(task.status.wire),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (task.isOverdue) ...[
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 15,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            decoration:
                                done ? TextDecoration.lineThrough : null,
                            color: done
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      StatusBadge(status: task.status, compact: true),
                      const SizedBox(width: Insets.sm),
                      PriorityBadge(priority: task.priority),
                      if (task.tags.isNotEmpty) ...[
                        const SizedBox(width: Insets.sm),
                        Flexible(
                          child: Text(
                            task.tags.map((t) => t.name).join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (showAssignee && task.assignee != null) ...[
                        UserAvatar(user: task.assignee, size: 20),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            task.assignee!.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: Insets.sm + 2),
                      ],
                      if (task.dueAt != null)
                        Icon(
                          task.isOverdue
                              ? Icons.event_busy_outlined
                              : Icons.event_outlined,
                          size: 13,
                          color: task.isOverdue
                              ? AppColors.danger
                              : AppColors.textMuted,
                        ),
                      const SizedBox(width: 3),
                      Text(
                        Format.dueLabel(
                          task.dueAt,
                          l10n,
                          overdue: task.isOverdue,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: task.isOverdue
                              ? AppColors.danger
                              : AppColors.textMuted,
                          fontWeight: task.isOverdue ? FontWeight.w600 : null,
                        ),
                      ),
                      if (task.commentsCount > 0) ...[
                        const SizedBox(width: Insets.sm + 2),
                        const Icon(
                          Icons.chat_bubble_outline,
                          size: 13,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${task.commentsCount}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                      if (task.attachmentsCount > 0) ...[
                        const SizedBox(width: Insets.sm),
                        const Icon(
                          Icons.attach_file,
                          size: 13,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${task.attachmentsCount}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка задачи для сетки на узких экранах.
class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, this.onTap});

  final Task task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Insets.radius),
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusBadge(status: task.status, compact: true),
                  const Spacer(),
                  PriorityBadge(priority: task.priority),
                ],
              ),
              const SizedBox(height: Insets.sm),
              Text(
                task.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              if (task.dueAt != null) ...[
                const SizedBox(height: Insets.sm),
                Row(
                  children: [
                    Icon(
                      task.isOverdue
                          ? Icons.event_busy_outlined
                          : Icons.event_outlined,
                      size: 14,
                      color: task.isOverdue
                          ? AppColors.danger
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        Format.dueLabel(
                          task.dueAt,
                          l10n,
                          overdue: task.isOverdue,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: task.isOverdue
                              ? AppColors.danger
                              : AppColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (task.assignee != null) ...[
                const SizedBox(height: Insets.sm),
                Row(
                  children: [
                    UserAvatar(user: task.assignee, size: 18),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        task.assignee!.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
