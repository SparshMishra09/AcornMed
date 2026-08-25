import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/performance_mode.dart';
import '../../data/services/knowledge_service.dart';
import '../../providers/chat_providers.dart';
import '../model_setup/model_setup_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _fast = false;

  @override
  void initState() {
    super.initState();
    loadFastMode().then((v) {
      if (mounted) setState(() => _fast = v);
    });
  }

  Future<void> _toggleFast(bool value) async {
    await setFastMode(value);
    if (mounted) setState(() => _fast = value);
    final ctrl = ref.read(chatControllerProvider.notifier);
    final file = ref.read(chatControllerProvider).modelFile;
    if (file != null) {
      // The new context size only takes effect after a reload.
      await ctrl.setModelFile(file);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reloading model with new speed profile')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    final knowledge = KnowledgeService.instance;
    final modelName = state.modelFile != null
        ? state.modelFile!.uri.pathSegments.last
        : 'No model installed';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionHeader(label: 'AI Model'),
          _SettingCard(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(Icons.smart_toy_outlined),
                title: const Text('Active model'),
                subtitle: Text(
                  modelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ModelSetupScreen(),
                    ),
                  );
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                secondary: const Icon(Icons.bolt_rounded),
                title: const Text('Faster responses'),
                subtitle: const Text(
                  'Uses a smaller context and shorter replies. Replies start '
                  'sooner and stream faster, with slightly less detail and a '
                  'smaller memory footprint.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
                value: _fast,
                onChanged: _toggleFast,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionHeader(label: 'Knowledge'),
          _SettingCard(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Bundled medical notes'),
                subtitle: Text(
                  knowledge.isReady
                      ? '${knowledge.bundledChunkCount} indexed passages across 6 subjects'
                      : 'Indexing…',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(Icons.library_books_outlined),
                title: const Text('Your documents'),
                subtitle: Text(
                  knowledge.documentChunkCount > 0
                      ? '${knowledge.documentChunkCount} indexed passages from your uploads'
                      : 'None added yet',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              const ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
                leading: Icon(Icons.public_rounded),
                title: Text('Web search'),
                subtitle: Text(
                  'Optional. When enabled (or for freshness questions), the '
                  'app queries PubMed, Wikipedia, and the web — no account '
                  'or API key needed. Only the search query leaves the device.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              const ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
                leading: Icon(Icons.wifi_off_rounded),
                title: Text('Privacy'),
                subtitle: Text(
                  'Chats, documents, and AI inference stay on this device. '
                  'No accounts, no API keys, no cloud.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionHeader(label: 'Data'),
          _SettingCard(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(
                  Icons.delete_sweep_outlined,
                  color: AppColors.error,
                ),
                title: const Text(
                  'Clear all conversations',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () => _confirmClear(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionHeader(label: 'About'),
          _SettingCard(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('AcornMed'),
                subtitle: const Text(
                  'Version 1.0.0 · A private, on-device AI study '
                  'companion for medical students.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(Icons.medical_information_outlined),
                title: const Text('Medical disclaimer'),
                subtitle: const Text(
                  'AcornMed is a study aid, not a medical professional. '
                  'Always verify with standard textbooks and qualified '
                  'clinicians before clinical use.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Clear all chats?'),
          content: const Text(
            'Every conversation will be permanently deleted from this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await ref
                    .read(chatControllerProvider.notifier)
                    .clearAllConversations();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All chats cleared')),
                  );
                }
              },
              child: const Text('Clear all'),
            ),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.sageDeep.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
