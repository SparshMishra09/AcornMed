import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show rootBundle;

void debugLog(String message) {
  if (kDebugMode) {
    print('[KnowledgeService] $message');
  }
}

class KnowledgeChunk {
  const KnowledgeChunk({
    required this.subject,
    required this.heading,
    required this.text,
    this.docId,
  });

  final String subject;
  final String heading;
  final String text;
  final String? docId;

  bool get isDocument => docId != null;
}

class KnowledgeService {
  KnowledgeService._();
  static final KnowledgeService instance = KnowledgeService._();

  static const List<String> _assetPaths = [
    'assets/knowledge/anatomy.md',
    'assets/knowledge/physiology.md',
    'assets/knowledge/pharmacology.md',
    'assets/knowledge/pathology.md',
    'assets/knowledge/biochemistry.md',
    'assets/knowledge/microbiology.md',
  ];

  final List<KnowledgeChunk> _chunks = [];
  final List<Map<String, double>> _chunkVectors = [];
  final Map<String, double> _idf = {};
  final Set<String> _indexedDocIds = {};
  bool _ready = false;

  /// Caps on injected RAG text. Lowered by "Faster responses" mode to shrink
  /// the prompt, which speeds up both prefill (time-to-first-token) and decode.
  int maxContextChars = 6000;
  int maxDocContextChars = 6000;

  bool get isReady => _ready;
  int get chunkCount => _chunks.length;
  int get bundledChunkCount =>
      _chunks.where((c) => !c.isDocument).length;
  int get documentChunkCount =>
      _chunks.where((c) => c.isDocument).length;

  static final Set<String> _stopWords = {
    'the', 'a', 'an', 'and', 'or', 'but', 'of', 'to', 'in', 'on', 'at',
    'for', 'with', 'by', 'from', 'is', 'are', 'was', 'were', 'be', 'been',
    'being', 'it', 'its', 'this', 'that', 'these', 'those', 'as', 'if',
    'than', 'then', 'so', 'such', 'into', 'about', 'what', 'which', 'who',
    'whom', 'when', 'where', 'why', 'how', 'do', 'does', 'did', 'can',
    'could', 'will', 'would', 'should', 'may', 'might', 'must', 'shall',
    'not', 'no', 'yes', 'i', 'you', 'he', 'she', 'we', 'they', 'them',
    'his', 'her', 'their', 'our', 'your', 'my', 'me', 'us', 'am', 'has',
    'have', 'had', 'there', 'here', 'all', 'any', 'some', 'each', 'per',
    'also', 'very', 'more', 'most', 'other', 'like', 'via', 'etc',
  };

  Future<void> init() async {
    if (_ready) return;
    for (final path in _assetPaths) {
      try {
        final content = await rootBundle.loadString(path);
        final subject = path.split('/').last.replaceAll('.md', '');
        _ingestMarkdown(subject, content);
      } catch (_) {
        // Missing knowledge file — skip silently.
      }
    }
    _buildIndex();
    _ready = true;
  }

  void ingestDocument({
    required String docId,
    required String name,
    required String text,
    bool rebuildIndex = true,
  }) {
    removeDocument(docId, rebuildIndex: false);
    _indexedDocIds.add(docId);
    final label = name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
    debugLog('Ingesting document: "$name" (${text.length} chars)');

    final lines = text.split('\n');
    final buffer = StringBuffer();
    var heading = label;
    var chunkIndex = 0;

    void flush() {
      final chunkText = buffer.toString().trim();
      if (chunkText.length > 40) {
        _chunks.add(KnowledgeChunk(
          subject: label,
          heading: heading,
          text: chunkText,
          docId: docId,
        ));
        final shortHeading = heading.length > 50 ? heading.substring(0, 50) : heading;
        debugLog('  Chunk #$chunkIndex: "$shortHeading..." (${chunkText.length} chars)');
        chunkIndex++;
      }
      buffer.clear();
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('## ') || trimmed.startsWith('# ')) {
        flush();
        heading = trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
      } else {
        buffer.writeln(line);
        if (buffer.length > 1400) {
          flush();
        }
      }
    }
    flush();
    // Rebuilding the TF-IDF index is O(chunks²)-ish; callers that ingest
    // many documents in a loop pass rebuildIndex:false and call
    // [rebuildIndex] once at the end.
    if (rebuildIndex) _buildIndex();
  }

  bool hasDocument(String docId) => _indexedDocIds.contains(docId);

  void rebuildIndex() => _buildIndex();

  void removeDocument(String docId, {bool rebuildIndex = true}) {
    _chunks.removeWhere((c) => c.docId == docId);
    _indexedDocIds.remove(docId);
    if (rebuildIndex) _buildIndex();
  }

  void _ingestMarkdown(String subject, String markdown) {
    final lines = markdown.split('\n');
    var heading = subject;
    final buffer = StringBuffer();

    void flush() {
      final text = buffer.toString().trim();
      if (text.length > 40) {
        _chunks.add(KnowledgeChunk(
          subject: subject,
          heading: heading,
          text: text,
        ));
      }
      buffer.clear();
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('## ')) {
        flush();
        heading = trimmed.substring(3).trim();
      } else if (trimmed.startsWith('# ')) {
        flush();
        heading = trimmed.substring(2).trim();
      } else {
        buffer.writeln(line);
        if (buffer.length > 1400) {
          flush();
        }
      }
    }
    flush();
  }

  List<String> _tokenize(String text) {
    final cleaned = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ');
    return cleaned
        .split(RegExp(r'[\s-]+'))
        .where((t) => t.length > 2 && !_stopWords.contains(t))
        .toList();
  }

  Map<String, double> _termFrequency(List<String> tokens) {
    final tf = <String, int>{};
    for (final t in tokens) {
      tf[t] = (tf[t] ?? 0) + 1;
    }
    return tf.map((k, v) => MapEntry(k, v.toDouble()));
  }

  void _buildIndex() {
    final docFreq = <String, int>{};
    final tfs = <Map<String, double>>[];
    for (final chunk in _chunks) {
      final tf = _termFrequency(_tokenize('${chunk.heading} ${chunk.text}'));
      tfs.add(tf);
      for (final term in tf.keys) {
        docFreq[term] = (docFreq[term] ?? 0) + 1;
      }
    }
    final n = max(1, _chunks.length);
    _idf.clear();
    docFreq.forEach((term, df) {
      _idf[term] = log((n + 1) / (df + 1)) + 1;
    });
    _chunkVectors.clear();
    for (final tf in tfs) {
      _chunkVectors.add(_vectorize(tf));
    }
  }

  Map<String, double> _vectorize(Map<String, double> tf) {
    final vec = <String, double>{};
    tf.forEach((term, count) {
      final idf = _idf[term];
      if (idf != null) {
        vec[term] = (1 + log(count)) * idf;
      }
    });
    return vec;
  }

  double _cosine(Map<String, double> a, Map<String, double> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    var dot = 0.0;
    final small = a.length <= b.length ? a : b;
    final large = identical(small, a) ? b : a;
    for (final entry in small.entries) {
      final other = large[entry.key];
      if (other != null) {
        dot += entry.value * other;
      }
    }
    if (dot == 0) return 0;
    var normA = 0.0;
    var normB = 0.0;
    for (final v in a.values) {
      normA += v * v;
    }
    for (final v in b.values) {
      normB += v * v;
    }
    return dot / (sqrt(normA) * sqrt(normB));
  }

  List<KnowledgeChunk> retrieve(
    String query, {
    int topK = 3,
    List<String>? docIds,
  }) {
    if (!_ready || _chunks.isEmpty) return const [];
    
    final queryVec = _vectorize(_termFrequency(_tokenize(query)));
    if (queryVec.isEmpty) return const [];

    debugLog('Retrieving - Query tokens: ${_tokenize(query).join(", ")}, vector size: ${queryVec.length}');
    
    final scored = <MapEntry<double, int>>[];
    for (var i = 0; i < _chunkVectors.length; i++) {
      final chunk = _chunks[i];
      if (docIds != null) {
        final chunkDoc = chunk.docId;
        if (chunkDoc == null || !docIds.contains(chunkDoc)) continue;
        final shortHeading = chunk.heading.length > 50 ? chunk.heading.substring(0, 50) : chunk.heading;
        debugLog('Checking doc chunk [${chunk.subject}: "$shortHeading..." - docId: $chunkDoc, match: ${docIds.contains(chunkDoc)}');
      }
      final score = _cosine(queryVec, _chunkVectors[i]);
      // Lower threshold for document-based retrieval to improve recall
      final threshold = docIds != null ? 0.04 : 0.08;
      if (score > threshold) {
        debugLog('  ✓ Score $score > threshold $threshold (chunk #${i + 1})');
        scored.add(MapEntry(score, i));
      } else {
        debugLog('  ✗ Score $score <= threshold $threshold (chunk #${i + 1})');
      }
    }
    scored.sort((a, b) => b.key.compareTo(a.key));
    final topScores = scored.take(5).map((e) {
      final shortHeading = _chunks[e.value].heading.length > 30 
          ? _chunks[e.value].heading.substring(0, 30) 
          : _chunks[e.value].heading;
      return "${e.key.toStringAsFixed(3)}:$shortHeading";
    }).join(", ");
    debugLog('Top scores before limit: $topScores');

    return scored
        .take(topK)
        .map((e) => _chunks[e.value])
        .toList();
  }

  List<KnowledgeChunk> getChunksForDocIds(List<String> docIds) {
    return _chunks.where((c) {
      final docId = c.docId;
      return docId != null && docIds.contains(docId);
    }).toList();
  }

  String buildContext(
    String query, {
    int topK = 3,
    List<String>? attachedDocIds,
  }) {
    debugLog('=== Building RAG context ===');
    debugLog('Query: "$query"');
    debugLog('Attached doc IDs: ${attachedDocIds?.join(", ") ?? "none"}');
    debugLog('Total chunks in index: ${_chunks.length}');
    if (attachedDocIds != null && attachedDocIds.isNotEmpty) {
      final userChunkCount = _chunks.where((c) => attachedDocIds.contains(c.docId)).length;
      final bundledChunkCount = _chunks.where((c) => c.docId == null).length;
      debugLog('User document chunks: $userChunkCount | Bundled chunks: $bundledChunkCount');
    }
    
    final sb = StringBuffer();

    if (attachedDocIds != null && attachedDocIds.isNotEmpty) {
      debugLog('Retrieving from ${attachedDocIds.length} document(s)...');
      final docHits = retrieve(query, topK: topK * 2, docIds: attachedDocIds);
      debugLog('Found ${docHits.length} matching passages from user documents');

      // Attached documents get priority in the context budget.
      final int maxDocContextChars = this.maxDocContextChars;

      if (docHits.isNotEmpty) {
        debugLog('Adding ${docHits.length} document passages to context');
        sb.writeln(
          'Relevant passages from the documents the student attached to this '
          'conversation (ground your answer in these where applicable):',
        );
        for (final hit in docHits) {
          if (sb.length >= maxDocContextChars) {
            debugLog('Doc context cap reached — truncating');
            break;
          }
          final shortHeading = hit.heading.length > 50 ? hit.heading.substring(0, 50) : hit.heading;
          debugLog('  - "${hit.subject}: $shortHeading" (${hit.text.length} chars)');
          sb.writeln('--- [Document "${hit.subject}": ${hit.heading}] ---');
          sb.writeln(hit.text);
          sb.writeln();
        }
      } else {
        debugLog('⚠️ NO MATCHING PASSAGES FOUND IN USER DOCUMENTS — using fallback');
        // Fallback: include first chunks from attached documents so "what's
        // in this document" style queries still see the content.
        final fallbackChunks = getChunksForDocIds(attachedDocIds);
        if (fallbackChunks.isNotEmpty) {
          debugLog('Adding fallback chunks from attached documents');
          sb.writeln(
            'Content from the documents the student attached to this conversation '
            '(no specific passages matched the query, so showing document content):',
          );
          // Limit to first 3 chunks per document to avoid overwhelming context
          final Map<String, int> docChunkCount = {};
          for (final chunk in fallbackChunks) {
            if (sb.length >= maxDocContextChars) {
              debugLog('Doc fallback cap reached — truncating');
              break;
            }
            final docId = chunk.docId!;
            final count = docChunkCount[docId] ?? 0;
            if (count < 3) {
              docChunkCount[docId] = count + 1;
              final shortHeading = chunk.heading.length > 50 ? chunk.heading.substring(0, 50) : chunk.heading;
              debugLog('  [fallback] - "${chunk.subject}: $shortHeading" (${chunk.text.length} chars)');
              sb.writeln('--- [Document "${chunk.subject}": ${chunk.heading}] ---');
              sb.writeln(chunk.text);
              sb.writeln();
            }
          }
        }
      }
    }

    debugLog('Retrieving from bundled knowledge base...');
    final kbHits = retrieve(query, topK: topK);
    debugLog('Found ${kbHits.length} matching passages from bundled knowledge');

    // Hard cap on injected context — a flood of passages (large documents,
    // many attachments) would otherwise overflow the model's context window
    // and push out the actual question.
    final int maxContextChars = this.maxContextChars;
    if (kbHits.isNotEmpty && sb.length < maxContextChars) {
      sb.writeln(
        'Relevant notes from the student\'s bundled knowledge base '
        '(use these to ground your answer where applicable):',
      );
      for (final hit in kbHits) {
        if (sb.length >= maxContextChars) {
          debugLog('Context cap reached — truncating bundled passages');
          break;
        }
        debugLog('  - "${hit.subject}: ${hit.heading}" (${hit.text.length} chars)');
        sb.writeln('--- [${hit.subject}: ${hit.heading}] ---');
        sb.writeln(hit.text);
        sb.writeln();
      }
    }
    
    debugLog('Context length: ${sb.toString().length} chars');
    debugLog('========================\n');

    return sb.toString();
  }

  void debugIndex() {
    debugLog('📊 KNOWLEDGE BASE DEBUG INDEX');
    debugLog('Total chunks: ${_chunks.length}');
    debugLog('--- User Document Chunks ---');
    for (var i = 0; i < _chunks.length; i++) {
      final chunk = _chunks[i];
      final shortHeading = chunk.heading.length > 60 ? chunk.heading.substring(0, 60) : chunk.heading;
      debugLog('[$i] subject="${chunk.subject}" heading="$shortHeading..." text_len=${chunk.text.length} docId=${chunk.docId ?? "(bundled)"}');
    }
  }
}
