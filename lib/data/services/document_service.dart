import 'dart:io';
import 'dart:isolate';

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
    final prefix = isError ? '[DocumentService] ERROR: ' : '[DocumentService] ';
    print('$prefix$message');
  }
}

/// Runs text extraction off the UI isolate so large PDFs don't freeze the
/// interface. [Isolate.run] transfers the result via `Isolate.exit`, so the
/// custom return type is safe.
Future<ExtractedDocument> _extractInIsolate(String filePath) {
  return Isolate.run(() {
    return DocumentExtractor.instance.extract(File(filePath));
  });
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

    final knowledge = KnowledgeService.instance;
    // Skip documents already ingested in this session (idempotent startup).
    final pending = docs
        .where((d) => !knowledge.hasDocument(d.id))
        .toList()
      ..removeWhere((d) => !File(d.filePath).existsSync());
    if (pending.isEmpty) {
      debugLog('All ${docs.length} document(s) already indexed');
      return;
    }

    debugLog('Reindexing ${pending.length} of ${docs.length} document(s)...');
    var success = 0;
    var failures = 0;

    for (final doc in pending) {
      try {
        final file = File(doc.filePath);
        if (!await file.exists()) {
          debugLog('  Document not found: ${doc.name}', isError: true);
          continue;
        }
        final extracted = await _extractInIsolate(file.path);
        knowledge.ingestDocument(
          docId: doc.id,
          name: doc.name,
          text: extracted.text,
          rebuildIndex: false,
        );
        debugLog('  Indexed "${doc.name}" (${extracted.text.length} chars)');
        success++;
      } catch (e) {
        debugLog('  Failed to index "${doc.name}": $e', isError: true);
        failures++;
      }
    }

    // One index build for the whole batch instead of one per document.
    knowledge.rebuildIndex();
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
    try {
      await source.copy(target.path);
    } catch (e) {
      throw const FormatException(
        'Could not read the selected file. It may have been moved or deleted.',
      );
    }

    debugLog('  Extracting text...');
    final ExtractedDocument extracted;
    try {
      extracted = await _extractInIsolate(target.path);
    } catch (e) {
      try {
        if (await target.exists()) await target.delete();
      } catch (_) {}
      rethrow;
    }

    if (extracted.text.trim().length < 20) {
      debugLog('  No readable text found (${extracted.text.length} chars)',
          isError: true);
      try {
        await target.delete();
      } catch (_) {}
      throw const FormatException(
        'No readable text found in this document. It may be a scanned '
        'image-only PDF.',
      );
    }

    debugLog(
      '  Extracted ${extracted.text.length} chars'
      '${extracted.pageCount != null ? ', ${extracted.pageCount} pages' : ''}',
    );

    final item = DocumentItem(
      id: id,
      name: name,
      filePath: target.path,
      addedAt: DateTime.now(),
      charCount: extracted.text.length,
      pageCount: extracted.pageCount,
    );
    await StorageService.instance.saveDocument(item);
    KnowledgeService.instance.ingestDocument(
      docId: id,
      name: name,
      text: extracted.text,
    );
    debugLog('  Document imported successfully');
    return item;
  }

  Future<void> deleteDocument(String id) async {
    final item = StorageService.instance.getDocument(id);
    if (item != null) {
      final file = File(item.filePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {
          // Best effort — the library entry is removed regardless.
        }
      }
    }
    await StorageService.instance.deleteDocument(id);
    KnowledgeService.instance.removeDocument(id);
  }
}
