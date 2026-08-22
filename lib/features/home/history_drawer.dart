import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo.dart';
import '../../data/models/conversation.dart';
import '../../providers/chat_providers.dart';
import '../documents/documents_screen.dart';
import '../settings/settings_screen.dart';

class HistoryDrawer extends ConsumerWidget {
  const HistoryDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final activeId = ref.watch(chatControllerProvider).conversation?.id;

    return Drawer(
      backgroundColor: AppColors.cream,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
              child: Row(
                children: [
                  const AppLogo(size: 42),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AcornMed',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.coffee,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Private · On-device AI',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.coffeeSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: () {
                  ref.read(chatControllerProvider.notifier).newConversation();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('New chat'),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: conversations.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No conversations yet.\nStart chatting!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.5,
                            color: AppColors.coffee.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final conversation = conversations[index];
                        return _ConversationTile(
                          conversation: conversation,
                          isActive: conversation.id == activeId,
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.library_books_outlined),
              title: const Text('Documents'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DocumentsScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({
    required this.conversation,
    required this.isActive,
  });

  final Conversation conversation;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateLabel = DateFormat.MMMd().format(conversation.updatedAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isActive ? AppColors.sageLight : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            ref
                .read(chatControllerProvider.notifier)
                .openConversation(conversation);
            Navigator.of(context).pop();
          },
          onLongPress: () => _showActions(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 18,
                  color: isActive
                      ? AppColors.sageDeep
                      : AppColors.coffeeSoft,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w500,
                          color: AppColors.coffee,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$dateLabel · ${conversation.messages.length} messages',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.coffeeSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    size: 18,
                    color: AppColors.coffeeSoft,
                  ),
                  onPressed: () => _showActions(context, ref),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _rename(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.error,
                ),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmDelete(context, ref);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _rename(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: conversation.title);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename chat'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Chat title'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  ref
                      .read(chatControllerProvider.notifier)
                      .renameConversation(conversation.id, text);
                }
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete chat?'),
          content: const Text(
            'This conversation will be permanently removed from your device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                ref
                    .read(chatControllerProvider.notifier)
                    .deleteConversation(conversation.id);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
