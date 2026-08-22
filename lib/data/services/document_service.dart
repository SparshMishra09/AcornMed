import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/document_item.dart';
import 'document_extractor.dart';
import 'knowledge_service.dart';
import 'storage_service.dart';

const _uuid = Uuid();

void debugLog(String message, {bool isError = false}) {
  if (kDebugMode) {
    final prefix = isError ? '✗ ERROR: ' : '✓ ';
    print('${DateTime.now().toIso8601String()} $prefix$message');
  }
}

class DocumentService {
  DocumentService._();
  static final DocumentService instance = DocumentService._();

  static const String _docsDirName = 'documents';

  Future<Directory> get _docsDir async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}/$_docsDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> reindexAll() async {
    final docs = StorageService.instance.getDocuments();
    if (docs.isEmpty) return;
    
    debugLog('Reindexing ${docs.length} document(s)...');
    var success = 0;
    var failures = 0;
    
    for (final doc in docs) {
      try {
        final file = File(doc.filePath);
        if (!await file.exists()) {
          debugLog('  ⚠️  Document not found: ${doc.name}');
          continue;
        }
        final extracted = await DocumentExtractor.instance.extract(file);
        KnowledgeService.instance.ingestDocument(
          docId: doc.id,
          name: doc.name,
          text: extracted.text,
        );
        debugLog('  ✓ Indexed "${doc.name}" (${extracted.text.length} chars)');
        success++;
      } catch (e, stack) {
        debugLog('  ✗ Failed to index "${doc.name}": $e', isError: true);
        debugLog(stack.toString());
        failures++;
      }
    }
    
    debugLog('Reindexing complete: $success succeeded, $failures failed');
  }

  Future<DocumentItem> importDocument(String sourcePath) async {
    final source = File(sourcePath);
    final name = source.uri.pathSegments.last;
    debugLog('Importing document: $name');
    
    if (!DocumentExtractor.instance.isSupported(name)) {
      throw const FormatException(
        'Unsupported file type. Use PDF, DOCX, TXT, or MD.',
      );
    }

    final dir = await _docsDir;
    final id = _uuid.v4();
    final target = File('${dir.path}/$id-$name');
    debugLog('  Copying to: ${target.path}');
    await source.copy(target.path);

    debugLog('  Extracting text...');
    final extracted = await DocumentExtractor.instance.extract(target);
    
    if (extracted.text.trim().length < 20) {
      debugLog('  ✗ No readable text found (${extracted.text.length} chars)', isError: true);
      await target.delete();
      throw const FormatException(
        'No readable text found in this document. It may be a scanned '
        'image-only PDF.',
      );
    }
    
    debugLog('  ✓ Extracted ${extracted.text.length} chars${extracted.pageCount != null ? ', ${extracted.pageCount} pages' : ''}');

    final item = DocumentItem(
      id: id,
      name: name,
      filePath: target.path,
      addedAt: DateTime.now(),
      charCount: extracted.text.length,
      pageCount: extracted.pageCount,
    );
    debugLog('  Saving to storage...');
    await StorageService.instance.saveDocument(item);
    debugLog('  Ingesting into knowledge base...');
    KnowledgeService.instance.ingestDocument(
      docId: id,
      name: name,
      text: extracted.text,
    );
    debugLog('  Document imported successfully!');
    return item;
  }

  Future<void> deleteDocument(String id) async {
    final item = StorageService.instance.getDocument(id);
    if (item != null) {
      final file = File(item.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await StorageService.instance.deleteDocument(id);
    KnowledgeService.instance.removeDocument(id);
  }
}
