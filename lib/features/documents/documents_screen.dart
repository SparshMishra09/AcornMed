import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/friendly_error.dart';
import '../../data/models/document_item.dart';
import '../../data/services/document_service.dart';
import '../../data/services/storage_service.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  bool _importing = false;
  int _version = 0;

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'docx', 'txt', 'md'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      var imported = 0;
      String? firstError;
      for (final file in result.files) {
        final path = file.path;
        if (path == null) {
          firstError ??=
              '"${file.name}" couldn\'t be opened. Try moving it to the '
              'Downloads folder and adding it again.';
          continue;
        }
        try {
          await DocumentService.instance.importDocument(path);
          imported++;
        } catch (e) {
          firstError ??= '"${file.name}": '
              '${e is FormatException ? e.message : friendlyError(e)}';
        }
      }
      if (!mounted) return;
      setState(() => _version++);
      if (imported > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$imported document${imported > 1 ? 's' : ''} added. '
              'The AI can now use ${imported > 1 ? 'them' : 'it'} in chats.',
            ),
          ),
        );
      }
      if (firstError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(firstError),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e)),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _confirmDelete(DocumentItem doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete document?'),
          content: Text(
            '"${doc.name}" will be removed from your library. '
            'The AI will no longer use it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await DocumentService.instance.deleteDocument(doc.id);
    if (!mounted) return;
    setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final documents = StorageService.instance.getDocuments();

    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        backgroundColor: AppColors.sageDark,
        foregroundColor: Colors.white,
        icon: _importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.upload_file_rounded),
        label: Text(_importing ? 'Reading…' : 'Add document'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              'Upload PDFs, DOCX, or text files. Their content is indexed '
              'on-device, and the AI uses it when you attach documents to a '
              'chat.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.coffee.withValues(alpha: 0.65),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: documents.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: AppColors.sage.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.library_books_outlined,
                              size: 48,
                              color: AppColors.sageDeep,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Your library is empty',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.coffee,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Add lecture notes, textbook chapters, or '
                            'guidelines — then attach them to any chat.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.5,
                              color:
                                  AppColors.coffee.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: documents.length,
                    itemBuilder: (context, index) {
                      return _DocumentCard(
                        doc: documents[index],
                        onDelete: () => _confirmDelete(documents[index]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.doc, required this.onDelete});

  final DocumentItem doc;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat.MMMd().format(doc.addedAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outlineSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.sagePale,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _iconFor(doc.extension),
              color: AppColors.sageDeep,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.coffee,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${doc.extension.toUpperCase()} · '
                  '${(doc.charCount / 1000).toStringAsFixed(1)}k chars'
                  '${doc.pageCount != null ? ' · ${doc.pageCount} pages' : ''}'
                  ' · $dateLabel',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.coffeeSoft,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.error,
            ),
            onPressed: onDelete,
          ),
        ],
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
