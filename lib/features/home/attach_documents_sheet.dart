import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/document_item.dart';
import '../../data/services/storage_service.dart';
import '../../providers/chat_providers.dart';
import '../documents/documents_screen.dart';

class AttachDocumentsSheet extends ConsumerWidget {
  const AttachDocumentsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = StorageService.instance.getDocuments();
    final attachedIds = ref.watch(chatControllerProvider).attachedDocIds;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineSoft,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Attach documents',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.coffee,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DocumentsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Selected documents are searched first when you ask questions '
                'in this chat.',
                style: TextStyle(fontSize: 12, color: AppColors.coffeeSoft),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: documents.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.folder_open_rounded,
                              size: 48,
                              color: AppColors.sage,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No documents yet.\nAdd PDFs, DOCX, or text files '
                              'in the Documents screen.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: AppColors.coffee
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const DocumentsScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.upload_file_rounded),
                              label: const Text('Go to Documents'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: documents.length,
                      itemBuilder: (context, index) {
                        final doc = documents[index];
                        final attached = attachedIds.contains(doc.id);
                        return _DocTile(
                          doc: doc,
                          attached: attached,
                          onToggle: () => ref
                              .read(chatControllerProvider.notifier)
                              .toggleDocumentAttachment(doc.id),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.doc,
    required this.attached,
    required this.onToggle,
  });

  final DocumentItem doc;
  final bool attached;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: attached ? AppColors.sageLight : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  _iconFor(doc.extension),
                  size: 22,
                  color: attached ? AppColors.sageDeep : AppColors.acorn,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.coffee,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${(doc.charCount / 1000).toStringAsFixed(1)}k characters',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.coffeeSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  attached
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: attached ? AppColors.sageDark : AppColors.outlineSoft,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String ext) {
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf_rounded,
      'docx' => Icons.description_rounded,
      _ => Icons.article_rounded,
    };
  }
}
