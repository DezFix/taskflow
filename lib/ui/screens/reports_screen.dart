/// Отчёты для главы отдела: сводка по задачам и нагрузка сотрудников.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/controllers.dart';
import '../file_save.dart';
import '../theme.dart';
import '../workspace_tab.dart';
import '../widgets.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportsProvider);
    final summary = state.summary;

    if (state.isLoading && summary == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (summary == null) {
      return EmptyState(
        icon: Icons.bar_chart_outlined,
        title: 'Отчёты недоступны',
        message: state.error,
        action: FilledButton(
          onPressed: () => ref.read(reportsProvider.notifier).load(),
          child: const Text('Повторить'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(reportsProvider.notifier).load(),
      child: ListView(
        padding: const EdgeInsets.all(Insets.md),
        children: [
          _CompletionCard(summary: summary),
          const SizedBox(height: Insets.md),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.9,
            crossAxisSpacing: Insets.sm,
            mainAxisSpacing: Insets.sm,
            children: [
              StatTile(
                label: 'Всего задач',
                value: '${summary.total}',
                icon: Icons.checklist_rtl,
                color: AppColors.primary,
                onTap: () => _openByStatus(context, ref, TaskStatus.created),
              ),
              StatTile(
                label: 'В работе',
                value: '${summary.countFor(TaskStatus.inProgress)}',
                icon: Icons.pending_actions,
                color: AppColors.info,
                onTap: () => _openByStatus(context, ref, TaskStatus.inProgress),
              ),
              StatTile(
                label: 'На проверке',
                value: '${summary.countFor(TaskStatus.review)}',
                icon: Icons.rate_review_outlined,
                color: AppColors.warning,
                onTap: () => _openByStatus(context, ref, TaskStatus.review),
              ),
              StatTile(
                label: 'Просрочено',
                value: '${summary.overdue}',
                icon: Icons.warning_amber_rounded,
                color: AppColors.danger,
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          _StatusBreakdown(summary: summary),
          const SizedBox(height: Insets.md),
          _WeeklyCard(summary: summary),
          const SizedBox(height: Insets.md),
          _LoadTable(rows: state.load),
          const SizedBox(height: Insets.md),
          _ExportCard(),
        ],
      ),
    );
  }

  Future<void> _openByStatus(
    BuildContext context,
    WidgetRef ref,
    TaskStatus status,
  ) async {
    // Переходим к задачам с выбранным статусом: сотрудник видит детали,
    // а не только цифру в отчёте. Меняем фильтр и уходим на вкладку
    // «Задачи» — раньше фильтр применялся, но список не открывался.
    ref
        .read(taskListProvider.notifier)
        .setFilter(TaskFilter(statuses: [status]));
    ref.read(workspaceTabProvider.notifier).state = WorkspaceTab.tasks;
  }
}

/// Круговой индикатор выполнения.
class _CompletionCard extends StatelessWidget {
  const _CompletionCard({
    required this.summary,
  });

  final TaskSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              height: 88,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 88,
                    height: 88,
                    child: CircularProgressIndicator(
                      value: (summary.completionRate / 100).clamp(0, 1),
                      strokeWidth: 9,
                      backgroundColor: AppColors.border,
                      color: AppColors.success,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${summary.completionRate.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Text(
                        'выполнено',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Legend(
                    color: AppColors.success,
                    label: 'Выполнено',
                    value: summary.countFor(TaskStatus.done),
                  ),
                  _Legend(
                    color: AppColors.warning,
                    label: 'На проверке',
                    value: summary.countFor(TaskStatus.review),
                  ),
                  _Legend(
                    color: AppColors.textMuted,
                    label: 'Отменено',
                    value: summary.countFor(TaskStatus.cancelled),
                  ),
                  _Legend(
                    color: AppColors.info,
                    label: 'Без исполнителя',
                    value: summary.unassigned,
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

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Text(
            '$value',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Распределение по статусам: полосы с подписями.
class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({
    required this.summary,
  });

  final TaskSummary summary;

  @override
  Widget build(BuildContext context) {
    final total = summary.total == 0 ? 1 : summary.total;

    return SectionCard(
      title: 'Распределение задач',
      child: Column(
        children: TaskStatus.values.map((status) {
          final count = summary.countFor(status);
          final ratio = count / total;

          return Padding(
            padding: const EdgeInsets.only(bottom: Insets.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      status.title,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const Spacer(),
                    Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: AppColors.border,
                    color: AppColors.statusColor(status.wire),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard({
    required this.summary,
  });

  final TaskSummary summary;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'За неделю',
      child: Row(
        children: [
          Expanded(
            child: _WeeklyStat(
              label: 'Создано задач',
              value: summary.createdThisWeek,
              icon: Icons.add_circle_outline,
              color: AppColors.primary,
            ),
          ),
          Container(width: 1, height: 44, color: AppColors.border),
          Expanded(
            child: _WeeklyStat(
              label: 'Завершено',
              value: summary.completedThisWeek,
              icon: Icons.check_circle_outline,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyStat extends StatelessWidget {
  const _WeeklyStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 5),
            Text(
              '$value',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Нагрузка по сотрудникам.
class _LoadTable extends StatelessWidget {
  const _LoadTable({
    required this.rows,
  });

  final List<UserLoad> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SectionCard(
        child: Text('Данных по сотрудникам пока нет'),
      );
    }

    return SectionCard(
      title: 'Нагрузка сотрудников',
      padding: const EdgeInsets.fromLTRB(
        Insets.md,
        Insets.md,
        Insets.md,
        Insets.sm,
      ),
      child: Column(
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: Insets.sm),
            // Строка открывает задачи сотрудника: из отчёта сотрудник
            // обычно и хочет перейти к его задачам, а не просто посмотреть.
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openEmployeeTasks(context, row),
              child: Row(
                children: [
                  UserAvatar(user: row.user, size: 30),
                  const SizedBox(width: Insets.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.user.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Всего: ${row.assigned} · в работе: ${row.inProgress} · '
                          'готово: ${row.completed}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (row.overdue > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${row.overdue} просрочено',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    Text(
                      '${row.completionRate.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Открывает список задач выбранного сотрудника.
void _openEmployeeTasks(BuildContext context, UserLoad row) {
  final assigneeId = row.user.id;
  if (assigneeId.isEmpty) return;

  // Тот же приём, что и у плиток статусов: фильтр плюс переход
  // на вкладку «Задачи».
  final container = ProviderScope.containerOf(context, listen: false);
  container.read(taskListProvider.notifier).setFilter(
        TaskFilter(assigneeId: assigneeId),
      );
  container.read(workspaceTabProvider.notifier).state = WorkspaceTab.tasks;
}

/// Выгрузка в CSV: открывается в Excel.
class _ExportCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      title: 'Выгрузка',
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'CSV со всеми задачами отдела. Откроется в Excel или '
              'LibreOffice, русский текст не поедет.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
          const SizedBox(width: Insets.sm),
          OutlinedButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final bytes =
                    await ref.read(reportsRepositoryProvider).exportTasksCsv();
                await saveDownloadedFile(
                  bytes,
                  fileName: 'taskflow_tasks.csv',
                  mimeType: 'text/csv',
                );
                messenger.showSnackBar(
                  const SnackBar(content: Text('Файл выгрузки сохранён')),
                );
              } on ApiException catch (error) {
                messenger.showSnackBar(SnackBar(content: Text(error.message)));
              } catch (error) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Не удалось сохранить файл: $error')),
                );
              }
            },
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Скачать'),
          ),
        ],
      ),
    );
  }
}

/// Открывает ссылку в браузере или системном приложении.

Future<void> openExternalUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Некорректный адрес: $url')));
    }
    return;
  }

  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }

  if (!opened && context.mounted) {
    // На некоторых устройствах системный обработчик не настроен: показываем
    // адрес, чтобы сотрудник мог открыть его вручную.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Откройте в браузере: $url'),
        duration: const Duration(seconds: 6),
      ),
    );
  }
}
