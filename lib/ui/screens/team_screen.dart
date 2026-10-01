/// Управление отделом: сотрудники, должности и роли.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../l10n/generated/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.teamTitle),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: l10n.teamTabStaff),
            Tab(text: l10n.teamTabPositions),
            Tab(text: l10n.teamTabRoles),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(directoryProvider.notifier).load(),
            tooltip: l10n.teamRefresh,
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
                    label: Text(l10n.teamAddStaff),
                  ),
                1 => FloatingActionButton.extended(
                    onPressed: _showCreatePosition,
                    icon: const Icon(Icons.badge_outlined),
                    label: Text(l10n.teamAddPosition),
                  ),
                _ => FloatingActionButton.extended(
                    onPressed: () => _showRoleEditor(context, null),
                    icon: const Icon(Icons.shield_outlined),
                    label: Text(l10n.teamAddRole),
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
    final l10n = AppLocalizations.of(context);
    final title = await showInputDialog<String>(
      context,
      title: l10n.teamNewPositionTitle,
      label: l10n.teamPositionNameLabel,
      hint: l10n.teamPositionNameHint,
      confirmText: l10n.teamCreate,
      validator: (value) => (value ?? '').trim().length < 2
          ? l10n.teamPositionNameRequired
          : null,
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
    final l10n = AppLocalizations.of(context);
    if (directory.users.isEmpty) {
      return EmptyState(
        icon: Icons.groups_outlined,
        title: l10n.teamEmptyStaffTitle,
        message: l10n.teamEmptyStaffMessage,
      );
    }

    final active = directory.users.where((u) => u.isActive).toList();
    final inactive = directory.users.where((u) => !u.isActive).toList();

    return ListView(
      children: [
        if (active.isNotEmpty) ...[
          _GroupHeader(l10n.teamGroupActive),
          ...active.map((user) => _UserTile(user: user)),
        ],
        if (inactive.isNotEmpty) ...[
          _GroupHeader(l10n.teamGroupInactive),
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
    final l10n = AppLocalizations.of(context);

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
            Text(
              l10n.teamThisIsYou,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
      subtitle: Text('${user.subtitle} · @${user.username}'),
      trailing: canEdit
          ? PopupMenuButton<String>(
              onSelected: (action) => _handle(context, ref, action),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'password',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.key_outlined),
                    title: Text(l10n.teamResetPassword),
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
                      user.isActive
                          ? l10n.teamDeactivate
                          : l10n.teamRestoreToTeam,
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
    final l10n = AppLocalizations.of(context);

    if (action == 'password') {
      final password = await showInputDialog<String>(
        context,
        title: l10n.teamResetPasswordTitle,
        message: l10n.teamResetPasswordMessage,
        label: l10n.teamNewPasswordLabel,
        confirmText: l10n.teamResetConfirm,
        obscureText: true,
        validator: (value) {
          final text = value ?? '';
          if (text.length < 8) return l10n.teamPasswordMinLength;
          if (!RegExp(r'\d').hasMatch(text)) {
            return l10n.teamPasswordNeedsDigits;
          }
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
            title: Text(l10n.teamPasswordResetDoneTitle),
            content: SelectableText(
              '${l10n.teamLoginLabel}: ${user.username}\n'
              '${l10n.teamPasswordLabel}: $result',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.teamDone),
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
        title: l10n.teamDeactivateTitle,
        message: '${user.displayName} ${l10n.teamDeactivateWarning}',
        confirmText: l10n.teamDeactivate,
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
    final l10n = AppLocalizations.of(context);
    if (directory.positions.isEmpty) {
      return EmptyState(
        icon: Icons.badge_outlined,
        title: l10n.teamEmptyPositionsTitle,
        message: l10n.teamEmptyPositionsMessage,
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
          title: Text(position.localizedTitle(l10n)),
          subtitle: Text(
            count == 0
                ? l10n.teamPositionNoStaff
                : '${l10n.teamPositionStaffCount}: $count',
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
    final l10n = AppLocalizations.of(context);
    if (directory.roles.isEmpty) {
      return EmptyState(
        icon: Icons.shield_outlined,
        title: l10n.teamEmptyRolesTitle,
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
          title: Text(role.localizedTitle(l10n)),
          subtitle: Text(
            '${l10n.teamPermissionsCount}: ${role.permissions.length}'
            ' · ${l10n.teamRolesStaffCount}: $count',
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
    final l10n = AppLocalizations.of(context);
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
                  _isEditing ? l10n.teamStaffTitle : l10n.teamNewStaffTitle,
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
                    decoration: InputDecoration(
                      labelText: l10n.teamLoginLabel,
                      helperText: l10n.teamLoginHelper,
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.length < 3) return l10n.teamLoginTooShort;
                      if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(text)) {
                        return l10n.teamLoginInvalidChars;
                      }
                      return null;
                    },
                  )
                else
                  InfoRow(
                    label: l10n.teamLoginLabel,
                    value: widget.existing!.username,
                  ),
                if (_isEditing) ...[
                  const SizedBox(height: Insets.sm),
                  InfoRow(
                    label: l10n.teamCreatedLabel,
                    value: Format.date(widget.existing!.createdAt, l10n),
                  ),
                ],
                const SizedBox(height: Insets.md),
                TextFormField(
                  controller: _fullNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      InputDecoration(labelText: l10n.teamFullNameLabel),
                  validator: (value) => (value ?? '').trim().length < 2
                      ? l10n.teamFullNameRequired
                      : null,
                ),
                const SizedBox(height: Insets.md),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: l10n.teamPhoneLabel),
                ),
                const SizedBox(height: Insets.md),
                TextFormField(
                  controller: _jobTitleController,
                  decoration: InputDecoration(
                    labelText: l10n.teamFreeformJobTitleLabel,
                  ),
                ),
                const SizedBox(height: Insets.md),
                DropdownButtonFormField<String?>(
                  initialValue: _positionId,
                  decoration:
                      InputDecoration(labelText: l10n.teamPositionFromList),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l10n.teamPositionUnassigned),
                    ),
                    ...widget.positions.map(
                      (position) => DropdownMenuItem<String?>(
                        value: position.id,
                        child: Text(position.localizedTitle(l10n)),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _positionId = value),
                ),
                const SizedBox(height: Insets.md),
                Text(
                  l10n.teamRolesAndPermissions,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
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
                    title: Text(role.localizedTitle(l10n)),
                    subtitle: Text(
                      '${l10n.teamPermissionsCount}: ${role.permissions.length}',
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: Insets.md),
                FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: Text(
                    _isEditing ? l10n.commonSave : l10n.teamCreateStaffButton,
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
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.teamSelectRoleRequired)),
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
        final l10n = AppLocalizations.of(context);
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.teamStaffCreatedTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.teamShareCredentialsHint),
                const SizedBox(height: Insets.md),
                SelectableText(
                  '${l10n.teamLoginLabel}: ${result.user.username}\n'
                  '${l10n.teamPasswordLabel}: '
                  '${result.temporaryPassword ?? "—"}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: Insets.md),
                Text(
                  l10n.teamPasswordShownOnce,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.teamDone),
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
    final l10n = AppLocalizations.of(context);
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
                  ? l10n.teamNewRoleTitle
                  : '${l10n.teamRoleTitle}: ${widget.role!.title}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Insets.md),
            if (widget.role == null)
              TextField(
                controller: _titleController,
                decoration: InputDecoration(labelText: l10n.teamRoleNameLabel),
              )
            else if (widget.role!.isSystem)
              Container(
                padding: const EdgeInsets.all(Insets.sm),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Insets.radiusSmall),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: AppColors.info,
                    ),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: Text(
                        l10n.teamSystemRoleHint,
                        style: const TextStyle(fontSize: 12),
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
                              allSelected
                                  ? l10n.teamDeselectAll
                                  : l10n.teamSelectAll,
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
                    ? l10n.teamCreateRoleButton
                    : '${l10n.commonSave} '
                        '(${_selected.length} ${l10n.teamPermissionsWord})',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (widget.role == null && _titleController.text.trim().length < 2) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.teamRoleNameRequired)),
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
