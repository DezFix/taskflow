/// Управление отделом: сотрудники, должности и роли.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/controllers.dart';
import '../theme.dart';
import '../widgets.dart';

class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final directory = ref.watch(directoryProvider);
    final user = ref.watch(currentUserProvider);
    final canManage = user?.can('users.create') ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Отдел'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Сотрудники'),
            Tab(text: 'Должности'),
            Tab(text: 'Роли'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(directoryProvider.notifier).load(),
            tooltip: 'Обновить',
          ),
        ],
      ),
      floatingActionButton: canManage
          ? AnimatedBuilder(
              animation: _tabs,
              builder: (context, _) => switch (_tabs.index) {
                0 => FloatingActionButton.extended(
                    onPressed: _showCreateUser,
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Сотрудник'),
                  ),
                1 => FloatingActionButton.extended(
                    onPressed: _showCreatePosition,
                    icon: const Icon(Icons.badge_outlined),
                    label: const Text('Должность'),
                  ),
                _ => FloatingActionButton.extended(
                    onPressed: () => _showRoleEditor(context, null),
                    icon: const Icon(Icons.shield_outlined),
                    label: const Text('Роль'),
                  ),
              },
            )
          : null,
      body: directory.isLoading && directory.users.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _UsersTab(directory: directory),
                _PositionsTab(directory: directory, canManage: canManage),
                _RolesTab(directory: directory, canManage: canManage),
              ],
            ),
    );
  }

  Future<void> _showCreateUser() async {
    final directory = ref.read(directoryProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _UserFormSheet(
        positions: directory.positions,
        roles: directory.roles,
      ),
    );
  }

  Future<void> _showCreatePosition() async {
    final title = await showInputDialog<String>(
      context,
      title: 'Новая должность',
      label: 'Название',
      hint: 'Например, DevOps-инженер',
      confirmText: 'Создать',
      validator: (value) =>
          (value ?? '').trim().length < 2 ? 'Введите название' : null,
    );
    if (title == null || !mounted) return;
    await ref.read(directoryProvider.notifier).createPosition(title.trim());
  }

  Future<void> _showRoleEditor(BuildContext context, Role? role) async {
    final repository = ref.read(directoryRepositoryProvider);
    List<PermissionInfo> permissions;
    try {
      permissions = await repository.permissions();
    } catch (error) {
      if (context.mounted) {
        ref.read(appErrorBusProvider).showError(error);
      }
      return;
    }
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RoleEditorSheet(
        role: role,
        permissions: permissions,
      ),
    );
  }
}

class _UsersTab extends ConsumerWidget {
  const _UsersTab({
    required this.directory,
  });

  final DirectoryState directory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (directory.users.isEmpty) {
      return const EmptyState(
        icon: Icons.groups_outlined,
        title: 'Сотрудников пока нет',
        message: 'Добавьте первого сотрудника, чтобы выдавать ему задачи',
      );
    }

    final active = directory.users.where((u) => u.isActive).toList();
    final inactive = directory.users.where((u) => !u.isActive).toList();

    return ListView(
      children: [
        if (active.isNotEmpty) ...[
          const _GroupHeader('Активные'),
          ...active.map((user) => _UserTile(user: user)),
        ],
        if (inactive.isNotEmpty) ...[
          const _GroupHeader('Отключённые'),
          ...inactive.map((user) => _UserTile(user: user)),
        ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        Insets.md,
        Insets.md,
        Insets.md,
        Insets.sm,
      ),
      color: AppColors.background,
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _UserTile extends ConsumerWidget {
  const _UserTile({
    required this.user,
  });

  final UserBrief user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    final canEdit = me?.can('users.edit') ?? false;

    return ListTile(
      leading: UserAvatar(user: user, size: 40),
      title: Row(
        children: [
          Flexible(
            child: Text(
              user.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (user.id == me?.id) ...[
            const SizedBox(width: 6),
            const Text(
              'это вы',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
      subtitle: Text('${user.subtitle} · @${user.username}'),
      trailing: canEdit
          ? PopupMenuButton<String>(
              onSelected: (action) => _handle(context, ref, action),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'password',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.key_outlined),
                    title: Text('Сбросить пароль'),
                  ),
                ),
                PopupMenuItem(
                  value: user.isActive ? 'deactivate' : 'activate',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      user.isActive
                          ? Icons.person_off_outlined
                          : Icons.person_add_alt,
                    ),
                    title: Text(
                      user.isActive ? 'Отключить' : 'Вернуть в отдел',
                    ),
                  ),
                ),
              ],
            )
          : null,
      onTap: canEdit
          ? () async {
              final directory = ref.read(directoryProvider);
              final full =
                  await ref.read(directoryRepositoryProvider).user(user.id);
              if (!context.mounted) return;
              await showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => _UserFormSheet(
                  existing: full,
                  positions: directory.positions,
                  roles: directory.roles,
                ),
              );
            }
          : null,
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final notifier = ref.read(directoryProvider.notifier);

    if (action == 'password') {
      final password = await showInputDialog<String>(
        context,
        title: 'Сброс пароля',
        message: 'Сотрудник получит временный пароль и должен будет '
            'сменить его при первом входе.',
        label: 'Новый пароль',
        confirmText: 'Сбросить',
        obscureText: true,
        validator: (value) {
          final text = value ?? '';
          if (text.length < 8) return 'Минимум 8 символов';
          if (!RegExp(r'\d').hasMatch(text)) return 'Нужны цифры';
          return null;
        },
      );
      if (password == null) return;

      try {
        final result = await ref
            .read(directoryRepositoryProvider)
            .resetPassword(user.id, newPassword: password);
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Пароль сброшен'),
            content: SelectableText(
              'Логин: ${user.username}\nПароль: $result',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Готово'),
              ),
            ],
          ),
        );
        await notifier.load();
      } catch (error) {
        if (context.mounted) ref.read(appErrorBusProvider).showError(error);
      }
      return;
    }

    if (action == 'deactivate') {
      final confirmed = await confirmDialog(
        context,
        title: 'Отключить сотрудника?',
        message:
            '${user.displayName} не сможет войти. История его задач и сообщений '
            'сохранится.',
        confirmText: 'Отключить',
      );
      if (confirmed) await notifier.setActive(user.id, false);
      return;
    }

    await notifier.setActive(user.id, true);
  }
}

class _PositionsTab extends ConsumerWidget {
  const _PositionsTab({
    required this.directory,
    required this.canManage,
  });

  final DirectoryState directory;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (directory.positions.isEmpty) {
      return const EmptyState(
        icon: Icons.badge_outlined,
        title: 'Должностей пока нет',
        message: 'Создайте должности, чтобы распределять сотрудников',
      );
    }

    return ListView.separated(
      itemCount: directory.positions.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final position = directory.positions[index];
        final count =
            directory.users.where((u) => u.position?.id == position.id).length;

        return ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: Text(position.title),
          subtitle: Text(
            count == 0 ? 'Никого не назначено' : 'Сотрудников: $count',
          ),
        );
      },
    );
  }
}

class _RolesTab extends ConsumerWidget {
  const _RolesTab({
    required this.directory,
    required this.canManage,
  });

  final DirectoryState directory;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (directory.roles.isEmpty) {
      return const EmptyState(
        icon: Icons.shield_outlined,
        title: 'Ролей пока нет',
      );
    }

    return ListView.separated(
      itemCount: directory.roles.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final role = directory.roles[index];
        final count = directory.users
            .where(
              (u) => u.roles.any((r) => r.id == role.id),
            )
            .length;

        return ListTile(
          leading: Icon(
            role.isSystem ? Icons.shield : Icons.shield_outlined,
            color: role.isSystem ? AppColors.primary : AppColors.textSecondary,
          ),
          title: Text(role.title),
          subtitle: Text(
            'Прав: ${role.permissions.length} · сотрудников: $count',
          ),
          trailing: canManage
              ? IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final repository = ref.read(directoryRepositoryProvider);
                    final permissions = await repository.permissions();
                    if (!context.mounted) return;
                    await showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => _RoleEditorSheet(
                        role: role,
                        permissions: permissions,
                      ),
                    );
                  },
                )
              : null,
        );
      },
    );
  }
}

/// Форма создания и редактирования сотрудника.
class _UserFormSheet extends ConsumerStatefulWidget {
  const _UserFormSheet({
    this.existing,
    required this.positions,
    required this.roles,
  });

  final AppUser? existing;
  final List<Position> positions;
  final List<Role> roles;

  @override
  ConsumerState<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends ConsumerState<_UserFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _usernameController = TextEditingController(
    text: widget.existing?.username ?? '',
  );
  late final _fullNameController = TextEditingController(
    text: widget.existing?.fullName ?? '',
  );
  late final _phoneController = TextEditingController(
    text: widget.existing?.phone ?? '',
  );
  late final _jobTitleController = TextEditingController(
    text: widget.existing?.jobTitle ?? '',
  );

  late String? _positionId = widget.existing?.position?.id;
  late final Set<String> _roleIds = {
    ...widget.existing?.roles.map((r) => r.id) ?? <String>{},
  };
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _jobTitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Insets.md,
          0,
          Insets.md,
          MediaQuery.of(context).viewInsets.bottom + Insets.md,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isEditing ? 'Сотрудник' : 'Новый сотрудник',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Insets.md),
                if (!_isEditing)
                  TextFormField(
                    controller: _usernameController,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Логин',
                      helperText: 'Латиница, цифры, точка, дефис',
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.length < 3) return 'Минимум 3 символа';
                      if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(text)) {
                        return 'Только латиница, цифры, точка, дефис';
                      }
                      return null;
                    },
                  )
                else
                  InfoRow(label: 'Логин', value: widget.existing!.username),
                if (_isEditing) ...[
                  const SizedBox(height: Insets.sm),
                  InfoRow(
                    label: 'Создан',
                    value: Format.date(widget.existing!.createdAt),
                  ),
                ],
                const SizedBox(height: Insets.md),
                TextFormField(
                  controller: _fullNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Имя и фамилия'),
                  validator: (value) =>
                      (value ?? '').trim().length < 2 ? 'Введите имя' : null,
                ),
                const SizedBox(height: Insets.md),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Телефон'),
                ),
                const SizedBox(height: Insets.md),
                TextFormField(
                  controller: _jobTitleController,
                  decoration: const InputDecoration(
                    labelText: 'Должность (свободным текстом)',
                  ),
                ),
                const SizedBox(height: Insets.md),
                DropdownButtonFormField<String?>(
                  initialValue: _positionId,
                  decoration:
                      const InputDecoration(labelText: 'Должность из списка'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Не назначена'),
                    ),
                    ...widget.positions.map(
                      (position) => DropdownMenuItem<String?>(
                        value: position.id,
                        child: Text(position.title),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _positionId = value),
                ),
                const SizedBox(height: Insets.md),
                const Text(
                  'Роли и права',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: Insets.sm),
                ...widget.roles.map(
                  (role) => CheckboxListTile(
                    value: _roleIds.contains(role.id),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        _roleIds.add(role.id);
                      } else {
                        _roleIds.remove(role.id);
                      }
                    }),
                    title: Text(role.title),
                    subtitle: Text('Прав: ${role.permissions.length}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: Insets.md),
                FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: Text(
                    _isEditing ? 'Сохранить' : 'Создать сотрудника',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_roleIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы одну роль')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final notifier = ref.read(directoryProvider.notifier);

    try {
      if (_isEditing) {
        await ref.read(directoryRepositoryProvider).updateUser(
              widget.existing!.id,
              fullName: _fullNameController.text.trim(),
              phone: _phoneController.text.trim(),
              jobTitle: _jobTitleController.text.trim(),
              // Пустое поле должно снимать должность, а не оставлять её.
              positionId: _positionId,
              clearPosition: _positionId == null,
              roleIds: _roleIds.toList(),
            );
        if (!mounted) return;
        Navigator.of(context).pop();
        await notifier.load();
      } else {
        final result = await notifier.createUser(
          username: _usernameController.text.trim(),
          fullName: _fullNameController.text.trim(),
          roleIds: _roleIds.toList(),
          phone: _phoneController.text.trim(),
          jobTitle: _jobTitleController.text.trim(),
          positionId: _positionId,
        );
        if (!mounted || result == null) return;

        // Временный пароль показываем один раз: сотрудник его запомнит.
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Сотрудник создан'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Передайте сотруднику данные для входа:'),
                const SizedBox(height: Insets.md),
                SelectableText(
                  'Логин: ${result.user.username}\n'
                  'Пароль: ${result.temporaryPassword ?? "—"}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: Insets.md),
                const Text(
                  'Пароль показывается один раз. При первом входе '
                  'сотрудник должен будет его сменить.',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Готово'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        await notifier.load();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ref.read(appErrorBusProvider).showError(error);
    }
  }
}

/// Редактор роли: название и матрица прав по группам.
class _RoleEditorSheet extends ConsumerStatefulWidget {
  const _RoleEditorSheet({
    required this.role,
    required this.permissions,
  });

  final Role? role;
  final List<PermissionInfo> permissions;

  @override
  ConsumerState<_RoleEditorSheet> createState() => _RoleEditorSheetState();
}

class _RoleEditorSheetState extends ConsumerState<_RoleEditorSheet> {
  late final Set<String> _selected = {...widget.role?.permissions ?? {}};
  late final _titleController = TextEditingController(
    text: widget.role?.title ?? '',
  );
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  /// Права, сгруппированные по разделам: так матрицу читать легче.
  Map<String, List<PermissionInfo>> get _grouped {
    final groups = <String, List<PermissionInfo>>{};
    for (final permission in widget.permissions) {
      groups.putIfAbsent(permission.group, () => []).add(permission);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _grouped;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Insets.md,
          0,
          Insets.md,
          MediaQuery.of(context).viewInsets.bottom + Insets.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.role == null
                  ? 'Новая роль'
                  : 'Роль: ${widget.role!.title}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Insets.md),
            if (widget.role == null)
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Название роли'),
              )
            else if (widget.role!.isSystem)
              Container(
                padding: const EdgeInsets.all(Insets.sm),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Insets.radiusSmall),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: AppColors.info),
                    SizedBox(width: Insets.sm),
                    Expanded(
                      child: Text(
                        'Системную роль нельзя удалить, но права можно менять',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Insets.md),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: groups.entries.map((entry) {
                  final groupPermissions = entry.value;
                  final allSelected = groupPermissions.every(
                    (p) => _selected.contains(p.key),
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              if (allSelected) {
                                for (final p in groupPermissions) {
                                  _selected.remove(p.key);
                                }
                              } else {
                                for (final p in groupPermissions) {
                                  _selected.add(p.key);
                                }
                              }
                            }),
                            child: Text(
                              allSelected ? 'Снять всё' : 'Выбрать всё',
                            ),
                          ),
                        ],
                      ),
                      ...groupPermissions.map(
                        (permission) => CheckboxListTile(
                          value: _selected.contains(permission.key),
                          onChanged: (checked) => setState(() {
                            if (checked == true) {
                              _selected.add(permission.key);
                            } else {
                              _selected.remove(permission.key);
                            }
                          }),
                          title: Text(
                            permission.title,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: permission.description.isEmpty
                              ? null
                              : Text(
                                  permission.description,
                                  style: const TextStyle(fontSize: 11),
                                ),
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 8),
                        ),
                      ),
                      const SizedBox(height: Insets.sm),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: Insets.sm),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: Text(
                widget.role == null
                    ? 'Создать роль'
                    : 'Сохранить (${_selected.length} прав)',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (widget.role == null && _titleController.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название роли')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final notifier = ref.read(directoryProvider.notifier);

    try {
      if (widget.role == null) {
        await notifier.createRole(
          title: _titleController.text.trim(),
          permissions: _selected.toList(),
        );
      } else {
        await notifier.updateRolePermissions(
            widget.role!.id, _selected.toList());
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ref.read(appErrorBusProvider).showError(error);
    }
  }
}
