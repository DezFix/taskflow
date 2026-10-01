/// Создание и редактирование задачи.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/controllers.dart';
import '../theme.dart';
import '../widgets.dart';

class TaskFormScreen extends ConsumerStatefulWidget {
  const TaskFormScreen({super.key, this.task});

  /// Если задача передана, форма редактирует её.
  final Task? task;

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController = TextEditingController(
    text: widget.task?.title ?? '',
  );
  late final _descriptionController = TextEditingController(
    text: widget.task?.description ?? '',
  );

  late TaskPriority _priority = widget.task?.priority ?? TaskPriority.normal;
  late String? _assigneeId = widget.task?.assignee?.id;
  late String? _assigneeName = widget.task?.assignee?.displayName;
  late DateTime? _dueAt = widget.task?.dueAt;
  late final Set<String> _tags = {
    ...widget.task?.tags.map((t) => t.name) ?? <String>{},
  };

  bool _isSaving = false;
  String? _error;

  bool get _isEditing => widget.task != null;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      if (_isEditing) {
        await ref.read(tasksRepositoryProvider).update(
              widget.task!.id,
              title: _titleController.text,
              description: _descriptionController.text,
              priority: _priority,
              dueAt: _dueAt,
              tags: _tags.toList(),
            );
      } else {
        await ref.read(taskListProvider.notifier).create(
              title: _titleController.text,
              description: _descriptionController.text,
              assigneeId: _assigneeId,
              priority: _priority,
              dueAt: _dueAt,
            );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = error is Exception
            ? AppLocalizations.of(context).taskFormSaveError
            : '$error';
      });
      ref.read(appErrorBusProvider).showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final canAssign = user?.can('tasks.assign') ?? false;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? l10n.taskFormEditTitle : l10n.taskFormCreateTitle,
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Insets.md),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Builder(
          builder: (context) => ListView(
            // Нижний отступ равен высоте клавиатуры: иначе при открытой
            // клавиатуре кнопку «Создать» было не прокрутить и она
            // оставалась срезанной нижней панелью.
            padding: EdgeInsets.fromLTRB(
              Insets.md,
              Insets.md,
              Insets.md,
              Insets.md + MediaQuery.viewInsetsOf(context).bottom,
            ),
            children: [
              TextFormField(
                controller: _titleController,
                autofocus: !_isEditing,
                maxLength: 300,
                decoration: InputDecoration(
                  labelText: l10n.taskFormTitleLabel,
                  counterText: '',
                ),
                validator: (value) => (value ?? '').trim().length < 3
                    ? l10n.taskFormTitleShort
                    : null,
              ),
              const SizedBox(height: Insets.md),
              TextFormField(
                controller: _descriptionController,
                maxLines: 5,
                maxLength: 20000,
                // Встроенный счётчик вылезал из поля и выглядел как
                // отдельная кнопка. Показываем количество символов
                // отдельной строкой под полем — предсказуемо и понятно,
                // к какому полю относится.
                decoration: InputDecoration(
                  labelText: l10n.taskFormDetailsLabel,
                  alignLabelWithHint: true,
                  counterText: '',
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _descriptionController,
                    builder: (context, value, _) => Text(
                      '${value.text.characters.length}/20000',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.sm),
              Text(
                l10n.taskFormPriorityLabel,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Insets.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: TaskPriority.values.map((priority) {
                  return ChoiceChip(
                    label: Text(priority.title(l10n)),
                    selected: _priority == priority,
                    onSelected: (_) => setState(() => _priority = priority),
                    avatar: _priority == priority
                        ? null
                        : Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.priorityColor(priority.wire),
                              shape: BoxShape.circle,
                            ),
                          ),
                  );
                }).toList(),
              ),
              const SizedBox(height: Insets.md),
              if (canAssign && !_isEditing) ...[
                Text(
                  l10n.taskAssigneeLabel,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: Insets.sm),
                _AssigneeField(
                  selectedId: _assigneeId,
                  selectedName: _assigneeName,
                  onChanged: (id, name) => setState(() {
                    _assigneeId = id;
                    _assigneeName = name;
                  }),
                ),
                const SizedBox(height: Insets.md),
              ],
              Text(
                l10n.taskDueLabel,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Insets.sm),
              _DueField(
                dueAt: _dueAt,
                onChanged: (value) => setState(() => _dueAt = value),
              ),
              const SizedBox(height: Insets.md),
              Text(
                l10n.taskFormTagsLabel,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Insets.sm),
              _TagsField(tags: _tags, onChanged: () => setState(() {})),
              const SizedBox(height: Insets.md),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: Insets.md),
              ],
              FilledButton(
                onPressed: _isSaving ? null : _save,
                child: Text(
                  _isEditing ? l10n.commonSave : l10n.taskFormCreateButton,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssigneeField extends ConsumerWidget {
  const _AssigneeField({
    required this.selectedId,
    required this.selectedName,
    required this.onChanged,
  });

  final String? selectedId;
  final String? selectedName;
  final void Function(String? id, String? name) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directory = ref.watch(directoryProvider);

    if (directory.isLoading) {
      return const LinearProgressIndicator();
    }

    final users = directory.users.where((u) => u.isActive).toList();
    final selected = selectedId == null
        ? null
        : users.where((u) => u.id == selectedId).firstOrNull;
    final l10n = AppLocalizations.of(context);

    return InputDecorator(
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.person_outline),
      ),
      child: InkWell(
        onTap: () => _showPicker(context, users),
        child: Row(
          children: [
            if (selected != null) ...[
              UserAvatar(user: selected, size: 22),
              const SizedBox(width: Insets.sm),
            ],
            Expanded(
              child: Text(
                selected?.displayName ?? l10n.taskAssigneeUnassigned,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context, List<UserBrief> users) async {
    final l10n = AppLocalizations.of(context);
    final result = await showModalBottomSheet<(String?, String?)>(
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
                Insets.sm,
              ),
              child: Text(
                l10n.taskAssigneePickerTitle,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: Text(l10n.taskAssigneeDoNotAssign),
              onTap: () => Navigator.of(sheetContext).pop((null, null)),
            ),
            const Divider(),
            ...users.map(
              (user) => ListTile(
                leading: UserAvatar(user: user),
                title: Text(user.displayName),
                subtitle: Text(user.subtitle),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop((user.id, user.displayName)),
              ),
            ),
          ],
        ),
      ),
    );
    if (result != null) onChanged(result.$1, result.$2);
  }
}

class _DueField extends StatelessWidget {
  const _DueField({
    required this.dueAt,
    required this.onChanged,
  });

  final DateTime? dueAt;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _pickDate(context),
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.event_outlined),
              ),
              child: Text(
                dueAt == null ? l10n.taskDueNone : Format.dateTime(dueAt, l10n),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ),
        if (dueAt != null) ...[
          const SizedBox(width: Insets.sm),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => onChanged(null),
            tooltip: l10n.taskDueClear,
          ),
        ],
      ],
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: dueAt?.toLocal() ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: l10n.taskDuePickerTitle,
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(dueAt?.toLocal() ?? now),
      helpText: l10n.taskDueTimePicker,
    );
    if (time == null) {
      onChanged(date);
      return;
    }
    onChanged(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }
}

class _TagsField extends ConsumerStatefulWidget {
  const _TagsField({
    required this.tags,
    required this.onChanged,
  });

  final Set<String> tags;
  final VoidCallback onChanged;

  @override
  ConsumerState<_TagsField> createState() => _TagsFieldState();
}

class _TagsFieldState extends ConsumerState<_TagsField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add([String? value]) async {
    final text = (value ?? _controller.text).trim();
    if (text.isEmpty) return;

    setState(() {
      widget.tags.add(text.length > 60 ? text.substring(0, 60) : text);
      _controller.clear();
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    // Подсказки из уже используемых меток: меньше опечаток в отчётах.
    final suggestions = <String>{};
    try {
      suggestions.addAll(ref
          .read(taskListProvider)
          .tasks
          .expand((t) => t.tags.map((tag) => tag.name))
          .toSet());
    } catch (_) {
      // Список задач мог быть ещё не загружен: подсказки необязательны.
    }
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: l10n.taskFormTagsHint,
            prefixIcon: const Icon(Icons.label_outline),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: _add,
            ),
          ),
          onSubmitted: _add,
        ),
        if (widget.tags.isNotEmpty) ...[
          const SizedBox(height: Insets.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.tags
                .map(
                  (tag) => Chip(
                    label: Text(tag),
                    onDeleted: () {
                      setState(() => widget.tags.remove(tag));
                      widget.onChanged();
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ],
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: Insets.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: suggestions
                .where((s) => !widget.tags.contains(s))
                .take(8)
                .map(
                  (s) => ActionChip(
                    label: Text(s),
                    onPressed: () => _add(s),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
