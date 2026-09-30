/// Экран списка задач с фильтрами и поиском.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/controllers.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/task_tile.dart';
import 'task_detail_screen.dart';
import 'task_form_screen.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(taskListProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Подгружаем следующую страницу заранее, до конца списка.
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(taskListProvider.notifier).loadMore();
    }
  }

  void _openSearch() {
    setState(() => _searching = true);
  }

  void _closeSearch() {
    setState(() {
      _searching = false;
      _searchController.clear();
    });
    final notifier = ref.read(taskListProvider.notifier);
    notifier.setFilter(notifier.filter.copyWith(search: ''));
  }

  Future<void> _createTask() async {
    // true — задача создана и список нужно обновить.
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TaskFormScreen()),
    );
    if (created == true && mounted) {
      await ref.read(taskListProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(taskListProvider);
    final user = ref.watch(currentUserProvider);
    final canCreate = user?.can('tasks.create') ?? false;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Поиск по задачам',
                  border: InputBorder.none,
                  filled: false,
                ),
                onSubmitted: (value) =>
                    ref.read(taskListProvider.notifier).setFilter(
                          ref.read(taskListProvider).filter.copyWith(
                                search: value,
                              ),
                        ),
              )
            : const Text('Задачи'),
        actions: [
          if (!_searching) ...[
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _openSearch,
              tooltip: 'Поиск',
            ),
            _FilterButton(
              count: state.filter.activeCount,
              onPressed: () => _openFilters(context),
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _closeSearch,
              tooltip: 'Закрыть поиск',
            ),
        ],
        bottom: _buildFilterBar(state),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _createTask,
              icon: const Icon(Icons.add),
              label: const Text('Задача'),
            )
          : null,
      body: _buildBody(state),
    );
  }

  /// Полоска активных фильтров: видно, что список сужен.
  PreferredSizeWidget? _buildFilterBar(TaskListState state) {
    final filter = state.filter;
    if (filter.activeCount == 0) return null;

    final labels = <String>[];
    if (filter.search.isNotEmpty) labels.add('«${filter.search}»');
    for (final status in filter.statuses) {
      labels.add(status.title);
    }
    for (final priority in filter.priorities) {
      labels.add(priority.title);
    }
    if (filter.overdueOnly) labels.add('Просроченные');
    if (filter.showArchived) labels.add('Архив');

    return PreferredSize(
      preferredSize: const Size.fromHeight(44),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: Insets.md),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: labels
                      .map(
                        (label) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Chip(
                            label: Text(label),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(taskListProvider.notifier).clearFilter(),
              child: const Text('Сбросить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(TaskListState state) {
    if (state.isLoading && state.tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.tasks.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off,
        title: 'Не удалось загрузить задачи',
        message: state.error,
        action: FilledButton.icon(
          onPressed: () => ref.read(taskListProvider.notifier).load(),
          icon: const Icon(Icons.refresh),
          label: const Text('Повторить'),
        ),
      );
    }

    if (state.isEmpty) {
      return EmptyState(
        icon: Icons.checklist_rtl,
        title: state.filter.activeCount > 0
            ? 'Ничего не найдено'
            : 'Задач пока нет',
        message: state.filter.activeCount > 0
            ? 'Попробуйте изменить условия фильтра'
            : 'Назначьте первую задачу сотруднику',
        action: state.filter.activeCount > 0
            ? OutlinedButton.icon(
                onPressed: () =>
                    ref.read(taskListProvider.notifier).clearFilter(),
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Сбросить фильтры'),
              )
            : null,
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(taskListProvider.notifier).refresh(),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.tasks.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.tasks.length) {
            return const Padding(
              padding: EdgeInsets.all(Insets.md),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final task = state.tasks[index];
          return TaskTile(
            task: task,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TaskDetailScreen(taskId: task.id),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openFilters(BuildContext context) async {
    final current = ref.read(taskListProvider).filter;
    final result = await showModalBottomSheet<TaskFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(initial: current),
    );
    if (result != null) {
      ref.read(taskListProvider.notifier).setFilter(result);
    }
  }
}

/// Кнопка фильтров с бейджем активных условий.
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.count,
    required this.onPressed,
  });

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.tune),
          onPressed: onPressed,
          tooltip: 'Фильтры',
        ),
        if (count > 0)
          Positioned(
            right: 6,
            top: 8,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Лист выбора фильтров.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initial,
  });

  final TaskFilter initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<TaskStatus> _statuses;
  late Set<TaskPriority> _priorities;
  late bool _overdue;
  late bool _archived;
  String? _assigneeId;
  String _assigneeName = '';

  @override
  void initState() {
    super.initState();
    // Поля инициализируем в initState: в декларации поля нельзя
    // обращаться к widget.
    _statuses = {...widget.initial.statuses};
    _priorities = {...widget.initial.priorities};
    _overdue = widget.initial.overdueOnly;
    _archived = widget.initial.showArchived;
    _assigneeId = widget.initial.assigneeId;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.md,
          0,
          Insets.md,
          Insets.md,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Фильтры',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: Insets.md),
              const Text(
                'Статус',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: Insets.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: TaskStatus.values.map((status) {
                  final selected = _statuses.contains(status);
                  return FilterChip(
                    label: Text(status.title),
                    selected: selected,
                    onSelected: (value) => setState(() {
                      if (value) {
                        _statuses.add(status);
                      } else {
                        _statuses.remove(status);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: Insets.md),
              const Text(
                'Приоритет',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: Insets.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: TaskPriority.values.map((priority) {
                  final selected = _priorities.contains(priority);
                  return FilterChip(
                    label: Text(priority.title),
                    selected: selected,
                    onSelected: (value) => setState(() {
                      if (value) {
                        _priorities.add(priority);
                      } else {
                        _priorities.remove(priority);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: Insets.md),
              const Text(
                'Исполнитель',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: Insets.sm),
              _AssigneePicker(
                selectedId: _assigneeId,
                selectedName: _assigneeName,
                onChanged: (id, name) => setState(() {
                  _assigneeId = id;
                  _assigneeName = name;
                }),
              ),
              const SizedBox(height: Insets.md),
              SwitchListTile(
                value: _overdue,
                onChanged: (value) => setState(() => _overdue = value),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Только просроченные'),
              ),
              SwitchListTile(
                value: _archived,
                onChanged: (value) => setState(() => _archived = value),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Показывать архивные'),
              ),
              const SizedBox(height: Insets.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(
                        TaskFilter(
                          search: widget.initial.search,
                          statuses: _statuses.toList(),
                          priorities: _priorities.toList(),
                          assigneeId: _assigneeId,
                          overdueOnly: _overdue,
                          showArchived: _archived,
                        ),
                      ),
                      child: const Text('Применить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Выбор исполнителя с поиском по отделу.
class _AssigneePicker extends ConsumerStatefulWidget {
  const _AssigneePicker({
    required this.selectedId,
    required this.selectedName,
    required this.onChanged,
  });

  final String? selectedId;
  final String selectedName;
  final void Function(String? id, String name) onChanged;

  @override
  ConsumerState<_AssigneePicker> createState() => _AssigneePickerState();
}

class _AssigneePickerState extends ConsumerState<_AssigneePicker> {
  @override
  Widget build(BuildContext context) {
    final directory = ref.watch(directoryProvider);
    final activeUsers = directory.users.where((u) => u.isActive).toList();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        FilterChip(
          label: const Text('Все'),
          selected: widget.selectedId == null,
          onSelected: (_) => widget.onChanged(null, ''),
        ),
        ...activeUsers.map(
          (user) => FilterChip(
            avatar: UserAvatar(user: user, size: 20),
            label: Text(user.displayName),
            selected: widget.selectedId == user.id,
            onSelected: (selected) => widget.onChanged(
              selected ? user.id : null,
              selected ? user.displayName : '',
            ),
          ),
        ),
      ],
    );
  }
}
