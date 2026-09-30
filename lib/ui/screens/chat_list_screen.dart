/// Список чатов: диалоги и группы с непрочитанными.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/controllers.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_screen.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatListProvider);
    final unread = ref.watch(unreadProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _startDialog(context, ref),
            tooltip: 'Новый диалог',
          ),
        ],
      ),
      body: _buildBody(context, ref, state),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _startDialog(context, ref),
        tooltip: 'Новый диалог',
        child: const Icon(Icons.add_comment_outlined),
      ),
      bottomNavigationBar: unread > 0
          ? Container(
              padding: const EdgeInsets.all(Insets.sm),
              color: AppColors.primary.withValues(alpha: 0.08),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    const Icon(
                      Icons.mark_email_unread_outlined,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: Insets.sm),
                    Text(
                      'Непрочитанных сообщений: $unread',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, ChatListState state) {
    if (state.isLoading && state.chats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.chats.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off,
        title: 'Не удалось загрузить чаты',
        message: state.error,
        action: FilledButton.icon(
          onPressed: () => ref.read(chatListProvider.notifier).load(),
          icon: const Icon(Icons.refresh),
          label: const Text('Повторить'),
        ),
      );
    }

    if (state.chats.isEmpty) {
      return EmptyState(
        icon: Icons.forum_outlined,
        title: 'Чатов пока нет',
        message: 'Начните диалог с коллегой или создайте группу отдела',
        action: FilledButton.icon(
          onPressed: () => _startDialog(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Начать диалог'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(chatListProvider.notifier).load(),
      child: ListView.separated(
        itemCount: state.chats.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) => _ChatTile(chat: state.chats[index]),
      ),
    );
  }

  Future<void> _startDialog(BuildContext context, WidgetRef ref) async {
    final directory = ref.watch(directoryProvider);
    if (directory.isLoading) {
      await ref.read(directoryProvider.notifier).load();
    }

    if (!context.mounted) return;

    final users = directory.users
        .where((u) => u.isActive && u.id != ref.read(currentUserProvider)?.id)
        .toList();

    if (users.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет других сотрудников для диалога'),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _NewChatSheet(users: users),
    );
  }
}

class _ChatTile extends ConsumerWidget {
  const _ChatTile({
    required this.chat,
  });

  final Chat chat;

  /// Собеседник в личном чате: тот участник, который не я сам.
  UserBrief? _counterpart(WidgetRef ref) {
    if (chat.members.isEmpty) return null;
    final me = ref.read(currentUserProvider);
    for (final member in chat.members) {
      if (me != null && member.id == me.id) continue;
      return member;
    }
    return chat.members.first;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle = chat.lastMessage?.preview ?? 'Нет сообщений';

    return ListTile(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chat.id,
            initialTitle: chat.displayTitle,
          ),
        ),
      ),
      leading: chat.isGroup
          ? const CircleAvatar(
              backgroundColor: AppColors.primary,
              child: Icon(Icons.groups, color: Colors.white),
            )
          // В личном чате показываем собеседника, а не первого
          // участника: первым в списке нередко оказывается сам
          // сотрудник, и тогда аватар совпадал бы с его фото.
          : UserAvatar(user: _counterpart(ref)),
      title: Row(
        children: [
          Expanded(
            child: Text(
              chat.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (chat.lastMessageAt != null)
            Text(
              Format.ago(chat.lastMessageAt),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (chat.unreadCount > 0) ...[
            const SizedBox(width: Insets.sm),
            UnreadBadge(count: chat.unreadCount),
          ] else if (chat.isMuted)
            const Icon(Icons.volume_off_outlined, size: 15),
        ],
      ),
    );
  }
}

/// Лист создания диалога или группы.
class _NewChatSheet extends ConsumerStatefulWidget {
  const _NewChatSheet({
    required this.users,
  });

  final List<UserBrief> users;

  @override
  ConsumerState<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<_NewChatSheet> {
  final _searchController = TextEditingController();
  final _selected = <String>{};
  late final _visible = widget.users.toList();
  bool _isGroup = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.toLowerCase();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.md,
          0,
          Insets.md,
          Insets.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Диалог'),
                  icon: Icon(Icons.person_outline),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Группа'),
                  icon: Icon(Icons.groups_outlined),
                ),
              ],
              selected: {_isGroup},
              onSelectionChanged: (value) =>
                  setState(() => _isGroup = value.first),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Поиск сотрудника',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
            const SizedBox(height: Insets.sm),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: widget.users
                    .where(
                      (user) =>
                          query.isEmpty ||
                          user.displayName.toLowerCase().contains(query) ||
                          user.username.toLowerCase().contains(query),
                    )
                    .map(
                      (user) => CheckboxListTile(
                        value: _selected.contains(user.id),
                        onChanged: (checked) => setState(() {
                          if (checked == true) {
                            _selected.add(user.id);
                          } else {
                            _selected.remove(user.id);
                          }
                        }),
                        secondary: UserAvatar(user: user),
                        title: Text(user.displayName),
                        subtitle: Text(user.subtitle),
                        dense: true,
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: Insets.sm),
            FilledButton(
              onPressed: _selected.isEmpty || _isSaving ? null : _create,
              child: Text(
                _isGroup
                    ? 'Создать группу (${_selected.length})'
                    : 'Открыть диалог',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    setState(() => _isSaving = true);
    final repository = ref.read(chatRepositoryProvider);

    try {
      if (_isGroup) {
        final title = _selected.map((id) => _nameOf(id)).take(3).join(', ');
        await repository.createGroup(
          title: title.isEmpty ? 'Новая группа' : title,
          memberIds: _selected.toList(),
        );
      } else {
        await repository.openDirect(_selected.first);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      await ref.read(chatListProvider.notifier).load();
    } catch (error) {
      if (!mounted) return;
      ref.read(appErrorBusProvider).showError(error);
      setState(() => _isSaving = false);
    }
  }

  String _nameOf(String id) {
    for (final user in _visible) {
      if (user.id == id) return user.displayName;
    }
    return 'Сотрудник';
  }
}
