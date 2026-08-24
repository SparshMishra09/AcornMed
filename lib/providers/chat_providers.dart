import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart' as llama;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/friendly_error.dart';
import '../data/models/chat_message.dart';
import '../data/models/conversation.dart';
import '../data/models/document_item.dart';
import '../data/models/web_source.dart';
import '../data/services/ai_engine.dart';
import '../data/services/knowledge_service.dart';
import '../data/services/model_manager.dart';
import '../data/services/ocr_service.dart';
import '../data/services/storage_service.dart';
import '../data/services/web_search_service.dart';

const _uuid = Uuid();

void debugLog(String message) {
  if (kDebugMode) {
    print('[ChatController] $message');
  }
}

final storageProvider = Provider<StorageService>((ref) => StorageService.instance);
final knowledgeProvider = Provider<KnowledgeService>((ref) => KnowledgeService.instance);
final modelManagerProvider = Provider<ModelManager>((ref) => ModelManager.instance);
final aiEngineProvider = Provider<AiEngine>((ref) => AiEngine.instance);

final engineStatusProvider = StreamProvider<EngineStatus>((ref) {
  return AiEngine.instance.statusStream;
});

class ChatState {
  const ChatState({
    this.conversation,
    this.isGenerating = false,
    this.isSearching = false,
    this.modelFile,
    this.modelLoading = false,
    this.modelError,
    this.pendingImagePath,
    this.pendingOcrText,
    this.ocrLoading = false,
    this.ocrError,
  });

  final Conversation? conversation;
  final bool isGenerating;
  final bool isSearching;
  final File? modelFile;
  final bool modelLoading;
  final String? modelError;
  final String? pendingImagePath;
  final String? pendingOcrText;
  final bool ocrLoading;
  final String? ocrError;

  List<ChatMessage> get messages => conversation?.messages ?? const [];
  List<String> get attachedDocIds => conversation?.attachedDocIds ?? const [];

  ChatState copyWith({
    Conversation? conversation,
    bool? isGenerating,
    bool? isSearching,
    File? modelFile,
    bool? modelLoading,
    String? modelError,
    bool clearModelError = false,
    String? pendingImagePath,
    bool clearPendingImage = false,
    String? pendingOcrText,
    bool clearPendingOcr = false,
    bool? ocrLoading,
    String? ocrError,
    bool clearOcrError = false,
  }) {
    return ChatState(
      conversation: conversation ?? this.conversation,
      isGenerating: isGenerating ?? this.isGenerating,
      isSearching: isSearching ?? this.isSearching,
      modelFile: modelFile ?? this.modelFile,
      modelLoading: modelLoading ?? this.modelLoading,
      modelError: clearModelError ? null : (modelError ?? this.modelError),
      pendingImagePath: clearPendingImage
          ? null
          : (pendingImagePath ?? this.pendingImagePath),
      pendingOcrText:
          clearPendingOcr ? null : (pendingOcrText ?? this.pendingOcrText),
      ocrLoading: ocrLoading ?? this.ocrLoading,
      ocrError: clearOcrError ? null : (ocrError ?? this.ocrError),
    );
  }
}

class _SearchDirectiveDetector {
  static const String marker = '[SEARCH:';
  static const int _maxBuffer = 300;

  final StringBuffer _buffer = StringBuffer();
  bool _failed = false;
  bool _complete = false;
  String? _query;

  bool get isFailed => _failed;
  bool get isComplete => _complete;
  String? get query => _query;
  String get buffered => _buffer.toString();

  void add(String token) {
    if (_failed || _complete) return;
    _buffer.write(token);
    final text = _buffer.toString().trimLeft();
    if (text.isEmpty) return;
    if (text.length > _maxBuffer) {
      _failed = true;
      return;
    }
    final isPrefixOfMarker = marker.startsWith(text);
    final hasMarker = text.startsWith(marker);
    if (!isPrefixOfMarker && !hasMarker) {
      _failed = true;
      return;
    }
    if (hasMarker) {
      final closeIdx = text.indexOf(']', marker.length);
      if (closeIdx != -1) {
        final candidate = text.substring(marker.length, closeIdx).trim();
        if (candidate.isEmpty) {
          _failed = true;
        } else {
          _query = candidate;
          _complete = true;
        }
      }
    }
  }
}

class ChatController extends Notifier<ChatState> {
  StreamSubscription<String>? _tokenSub;
  Completer<void>? _activeCompleter;
  bool _stopRequested = false;

  static const int _maxHistoryMessages = 10;
  static const int _maxOcrChars = 4000;

  @override
  ChatState build() {
    ref.onDispose(() => _tokenSub?.cancel());
    return const ChatState();
  }

  Future<void> init() async {
    final file = await ModelManager.instance.getActiveModelFile();
    state = state.copyWith(modelFile: file, clearModelError: true);
    if (file != null) {
      await _ensureModelLoaded(file);
    }
  }

  Future<void> _ensureModelLoaded(File file) async {
    final engine = AiEngine.instance;
    if (engine.isReady && engine.loadedModelPath == file.path) return;
    state = state.copyWith(modelLoading: true, clearModelError: true);
    try {
      await engine.loadModel(file);
      state = state.copyWith(modelLoading: false, modelFile: file);
    } catch (e) {
      state = state.copyWith(
        modelLoading: false,
        modelError:
            'This model couldn\'t be loaded. It may be damaged or too large '
            'for this device — try re-downloading it, or pick the smaller '
            'model in Settings.',
      );
      debugLog('Model load failed: $e');
    }
  }

  Future<void> setModelFile(File file) async {
    await AiEngine.instance.unload();
    state = ChatState(
      conversation: state.conversation,
      modelFile: file,
    );
    await _ensureModelLoaded(file);
  }

  Future<void> unloadActiveModel() async {
    await AiEngine.instance.unload();
    state = ChatState(conversation: state.conversation);
  }

  void newConversation() {
    final now = DateTime.now();
    final conversation = Conversation(
      id: _uuid.v4(),
      title: 'New chat',
      createdAt: now,
      updatedAt: now,
    );
    state = state.copyWith(
      conversation: conversation,
      clearPendingImage: true,
      clearPendingOcr: true,
      clearOcrError: true,
    );
  }

  void openConversation(Conversation conversation) {
    state = state.copyWith(
      conversation: conversation,
      clearPendingImage: true,
      clearPendingOcr: true,
      clearOcrError: true,
    );
  }

  Future<void> deleteConversation(String id) async {
    if (state.conversation?.id == id && state.isGenerating) {
      await stopGenerating();
    }
    final conversation = StorageService.instance.getConversation(id);
    await _deleteMessageImages(conversation);
    await StorageService.instance.deleteConversation(id);
    if (state.conversation?.id == id) {
      final modelFile = state.modelFile;
      state = ChatState(modelFile: modelFile);
    }
  }

  Future<void> clearAllConversations() async {
    if (state.isGenerating || state.isSearching) {
      await stopGenerating();
    }
    for (final conversation in StorageService.instance.getConversations()) {
      await _deleteMessageImages(conversation);
    }
    await StorageService.instance.clearAll();
    final modelFile = state.modelFile;
    state = ChatState(modelFile: modelFile);
  }

  Future<void> _deleteMessageImages(Conversation? conversation) async {
    if (conversation == null) return;
    for (final message in conversation.messages) {
      final path = message.imagePath;
      if (path == null) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }

  Future<void> renameConversation(String id, String title) async {
    final conversation = StorageService.instance.getConversation(id);
    if (conversation == null) return;
    conversation.title = title;
    await StorageService.instance.saveConversation(conversation);
    if (state.conversation?.id == id) {
      state = state.copyWith(conversation: conversation);
    }
  }

  Future<void> toggleDocumentAttachment(String docId) async {
    var conversation = state.conversation;
    if (conversation == null) {
      final now = DateTime.now();
      conversation = Conversation(
        id: _uuid.v4(),
        title: 'New chat',
        createdAt: now,
        updatedAt: now,
      );
    }
    if (conversation.attachedDocIds.contains(docId)) {
      conversation.attachedDocIds.remove(docId);
    } else {
      conversation.attachedDocIds.add(docId);
    }
    // Only persist conversations that have real content; otherwise the
    // history fills up with empty "New chat" entries.
    if (conversation.messages.isNotEmpty) {
      await StorageService.instance.saveConversation(conversation);
    }
    state = state.copyWith(conversation: conversation);
  }

  Future<void> attachImage({required ImageSource source}) async {
    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
    } catch (_) {
      return; // User denied permission or picker crashed.
    }
    if (picked == null) return;

    final appDir = await getApplicationSupportDirectory();
    final imagesDir = Directory('${appDir.path}/images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    var ext = picked.path.split('.').last.toLowerCase();
    if (ext.isEmpty || ext.length > 5 || !RegExp(r'^[a-z0-9]+$').hasMatch(ext)) {
      ext = 'jpg';
    }
    final target = File('${imagesDir.path}/${_uuid.v4()}.$ext');
    try {
      await File(picked.path).copy(target.path);
    } catch (_) {
      state = state.copyWith(
        clearPendingImage: true,
        ocrError: 'Could not load the selected image.',
      );
      return;
    }

    state = state.copyWith(
      pendingImagePath: target.path,
      ocrLoading: true,
      clearOcrError: true,
      clearPendingOcr: true,
    );

    try {
      var text = await OcrService.instance.recognizeText(target.path);
      if (text.length > _maxOcrChars) {
        text = '${text.substring(0, _maxOcrChars)}…';
      }
      state = state.copyWith(
        ocrLoading: false,
        pendingOcrText: text.isEmpty ? null : text,
      );
    } catch (e) {
      state = state.copyWith(
        ocrLoading: false,
        ocrError: 'Couldn\'t read text from this image — you can still send '
            'it, or try a clearer, well-lit photo.',
      );
      debugLog('OCR failed: $e');
    }
  }

  void clearPendingImage() {
    state = state.copyWith(
      clearPendingImage: true,
      clearPendingOcr: true,
      clearOcrError: true,
    );
  }

  bool _looksLikeFreshnessQuery(String text) {
    final lower = text.toLowerCase();
    const triggers = [
      'latest',
      'newest',
      'most recent',
      'recent study',
      'recent research',
      'current guideline',
      'current guidelines',
      'current recommendation',
      'updated guideline',
      'new treatment',
      'newly approved',
      'new drug',
      'fda approval',
      'new evidence',
      'as of now',
      'this year',
      'breaking',
      'state of the art',
      'upcoming',
      'when is the next',
      'announcement',
    ];
    if (triggers.any(lower.contains)) return true;
    final year = DateTime.now().year;
    return RegExp('\\b($year|${year - 1})\\b').hasMatch(lower);
  }

  Future<void> sendMessage(String text, {bool webSearch = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isGenerating || state.isSearching) return;
    _stopRequested = false;

    final engine = AiEngine.instance;
    if (!engine.isReady) {
      if (state.modelFile != null) {
        await _ensureModelLoaded(state.modelFile!);
      }
      if (!engine.isReady) return;
    }

    var existing = state.conversation;
    if (existing == null) {
      final now = DateTime.now();
      existing = Conversation(
        id: _uuid.v4(),
        title: trimmed.length > 34 ? '${trimmed.substring(0, 34)}…' : trimmed,
        createdAt: now,
        updatedAt: now,
      );
    }
    final conversation = existing;

    final userMessage = ChatMessage(
      id: _uuid.v4(),
      role: 'user',
      content: trimmed,
      timestamp: DateTime.now(),
      imagePath: state.pendingImagePath,
      ocrText: state.pendingOcrText,
    );
    conversation.messages.add(userMessage);
    if (conversation.messages.where((m) => m.isUser).length == 1) {
      conversation.title =
          trimmed.length > 34 ? '${trimmed.substring(0, 34)}…' : trimmed;
    }
    conversation.updatedAt = DateTime.now();
    // Persist the user's message immediately so it survives an app kill
    // mid-generation.
    _save(conversation);

    final imagePath = state.pendingImagePath;
    final ocrText = state.pendingOcrText;
    final assistantMessage = ChatMessage(
      id: _uuid.v4(),
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
    );
    conversation.messages.add(assistantMessage);
    state = state.copyWith(
      conversation: conversation,
      isGenerating: true,
      clearPendingImage: true,
      clearPendingOcr: true,
    );

    List<WebSearchResult>? searchResults;
    final wantsSearch = webSearch || _looksLikeFreshnessQuery(trimmed);
    if (wantsSearch) {
      state = state.copyWith(isSearching: true, isGenerating: false);
      searchResults = await WebSearchService.instance.search(trimmed);
      state = state.copyWith(isSearching: false, isGenerating: true);
    }

    await _generate(
      conversation: conversation,
      assistantMessage: assistantMessage,
      userText: trimmed,
      ocrText: ocrText,
      hasImage: imagePath != null,
      searchResults: searchResults,
      allowSearchIntercept: searchResults == null || searchResults.isEmpty,
      webSearchWasRequested: webSearch,
    );
  }

  /// Removes empty assistant bubbles (e.g. after a stop or a crash) and
  /// persists the conversation.
  void _save(Conversation conversation) {
    conversation.messages
        .removeWhere((m) => m.isAssistant && m.content.isEmpty);
    conversation.updatedAt = DateTime.now();
    StorageService.instance.saveConversation(conversation);
  }

  Future<void> _generate({
    required Conversation conversation,
    required ChatMessage assistantMessage,
    required String userText,
    String? ocrText,
    bool hasImage = false,
    List<WebSearchResult>? searchResults,
    required bool allowSearchIntercept,
    bool webSearchWasRequested = false,
  }) async {
    final engine = AiEngine.instance;

    if (conversation.attachedDocIds.isNotEmpty) {
      debugLog(
        '📎 ${conversation.attachedDocIds.length} document(s) attached: '
        '${conversation.attachedDocIds.join(", ")}',
      );
    }

    final ragContext = KnowledgeService.instance.buildContext(
      userText,
      attachedDocIds: conversation.attachedDocIds,
    );
    debugLog('RAG context generated: ${ragContext.length} chars');

    final systemBuffer = StringBuffer(kMedicalSystemPrompt);
    if (ragContext.isNotEmpty) {
      systemBuffer.writeln();
      systemBuffer.writeln(ragContext);
    }
    if (ocrText != null && ocrText.isNotEmpty) {
      systemBuffer.writeln();
      systemBuffer.writeln(
        'The student attached an image. Text extracted from it via on-device '
        'OCR is below. Analyze this content and help the student with it:\n'
        '"""\n$ocrText\n"""',
      );
    } else if (hasImage) {
      systemBuffer.writeln();
      systemBuffer.writeln(
        'The student attached an image, but no readable text could be '
        'extracted from it. Note that you are a text model: describe what '
        'you can help with regarding the image topic if the student provides '
        'details, and be honest that you cannot see the image directly.',
      );
    }
    if (searchResults != null && searchResults.isNotEmpty) {
      systemBuffer.writeln();
      systemBuffer.writeln(
        WebSearchService.instance.buildContext(searchResults),
      );
      // Critical: the base prompt tells the model to emit [SEARCH:] when it
      // lacks current info. Now that results are already attached, that
      // instruction must be overridden — otherwise the model prints the raw
      // directive into the chat instead of answering.
      systemBuffer.writeln();
      systemBuffer.writeln(
        'Live web results are provided above. Answer using them now: do NOT '
        'reply with [SEARCH:] again, do not mention being unable to search, '
        'and cite sources by their numbers where you use them.',
      );
    } else if (webSearchWasRequested) {
      // The user explicitly asked for web search but it came back empty —
      // say so honestly instead of pretending.
      systemBuffer.writeln();
      systemBuffer.writeln(
        'Note: a live web search was attempted for this question but returned '
        'no usable results. Answer from your own knowledge, and briefly tell '
        'the student you could not verify this online.',
      );
    }

    // Cap history so long chats cannot overflow the model's context window.
    final past = conversation.messages
        .where((m) => m.id != assistantMessage.id && m.content.isNotEmpty)
        .toList();
    final history = past.length > _maxHistoryMessages
        ? past.sublist(past.length - _maxHistoryMessages)
        : past;

    final llamaMessages = <llama.ChatMessage>[
      llama.ChatMessage(role: 'system', content: systemBuffer.toString()),
      for (final m in history)
        llama.ChatMessage(
          role: m.role,
          content: m.isUser && m.ocrText != null && m.ocrText!.isNotEmpty
              ? '${m.content}\n\n[Text extracted from the attached image]: ${m.ocrText}'
              : m.content,
        ),
    ];

    // The detector ALWAYS watches for the [SEARCH:] directive — small models
    // emit it even when they've been told not to. What differs is what we do
    // with it:
    //  • intercept allowed  → capture it and run a real search.
    //  • intercept disabled → silently swallow the directive text and keep
    //    streaming the rest of the reply (it must never reach the chat).
    final detector = _SearchDirectiveDetector();
    var buffering = true; // Feeding the detector; tokens held temporarily.
    var captured = false; // Directive fully seen; drop remaining tokens.

    void appendToken(String token) {
      assistantMessage.content += token;
      if (state.conversation?.id == conversation.id) {
        state = state.copyWith(conversation: conversation);
      }
    }

    try {
      final stream = engine.chat(messages: llamaMessages);
      final completer = Completer<void>();
      _activeCompleter = completer;
      _tokenSub = stream.listen(
        (token) {
          if (!buffering) {
            if (!captured) appendToken(token);
            return;
          }
          detector.add(token);
          if (detector.isFailed) {
            // Normal answer text — flush what we held and stream directly.
            assistantMessage.content += detector.buffered;
            buffering = false;
            if (state.conversation?.id == conversation.id) {
              state = state.copyWith(conversation: conversation);
            }
          } else if (detector.isComplete) {
            if (allowSearchIntercept) {
              captured = true; // Hold nothing more; intercept after stream.
            } else {
              buffering = false; // Drop the directive, keep the rest.
            }
          }
        },
        onError: (Object e) {
          if (assistantMessage.content.isEmpty) {
            assistantMessage.content = friendlyError(e);
            assistantMessage.isError = true;
          }
          _save(conversation);
          if (state.conversation?.id == conversation.id) {
            state = state.copyWith(conversation: conversation, isGenerating: false);
          }
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (buffering) {
            // Stream ended mid-buffer (short reply, or a truncated
            // directive) — show what we held as plain text.
            assistantMessage.content += detector.buffered;
          }
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      await completer.future;
      if (identical(_activeCompleter, completer)) {
        _activeCompleter = null;
        _tokenSub = null;
      }
    } catch (e) {
      assistantMessage.content = friendlyError(e);
      assistantMessage.isError = true;
      _save(conversation);
      state = state.copyWith(conversation: conversation, isGenerating: false);
      return;
    }

    // If the user stopped generation, don't run a deferred web search or keep
    // streaming — just persist what we have (empty bubbles get stripped later).
    if (_stopRequested) {
      assistantMessage.content = assistantMessage.content
          .replaceAll(RegExp(r'\[\s*SEARCH\s*:[^\]]*\]'), '')
          .trim();
      _save(conversation);
      if (state.conversation?.id == conversation.id) {
        state = state.copyWith(conversation: conversation, isGenerating: false);
      }
      return;
    }

    if (captured && allowSearchIntercept) {
      final query = WebSearchService.instance.sanitizeQuery(detector.query ?? '');
      assistantMessage.content = '';
      state = state.copyWith(isSearching: true, isGenerating: false);
      final results = query.isEmpty
          ? const <WebSearchResult>[]
          : await WebSearchService.instance.search(query);
      state = state.copyWith(isSearching: false, isGenerating: true);
      if (results.isNotEmpty) {
        await _generate(
          conversation: conversation,
          assistantMessage: assistantMessage,
          userText: userText,
          ocrText: ocrText,
          hasImage: hasImage,
          searchResults: results,
          allowSearchIntercept: false,
          webSearchWasRequested: webSearchWasRequested,
        );
        return;
      }
      assistantMessage.content =
          'I couldn\'t find anything useful online for that. Try rephrasing, '
          'or ask me about it and I\'ll answer from what I know.';
      assistantMessage.isError = false;
    }

    // Belt and braces: no [SEARCH:] directive should ever survive into a
    // saved/displayed message.
    final cleaned = assistantMessage.content
        .replaceAll(RegExp(r'\[\s*SEARCH\s*:[^\]]*\]'), '')
        .trim();
    if (cleaned != assistantMessage.content) {
      assistantMessage.content = cleaned;
    }

    if (searchResults != null && searchResults.isNotEmpty) {
      assistantMessage.sources = searchResults
          .take(6)
          .map((r) => WebSource(
                title: r.title,
                url: r.url,
                source: r.source,
                date: r.date,
              ))
          .toList();
      assistantMessage.webSearched = true;
    }

    if (assistantMessage.content.isEmpty) {
      assistantMessage.content =
          'The model returned an empty response. Please try again.';
      assistantMessage.isError = true;
    }
    _save(conversation);
    state = state.copyWith(conversation: conversation, isGenerating: false);
  }

  Future<void> stopGenerating() async {
    _stopRequested = true;
    await AiEngine.instance.stop();
    await _tokenSub?.cancel();
    _tokenSub = null;
    final completer = _activeCompleter;
    _activeCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    final conversation = state.conversation;
    if (conversation != null) {
      _save(conversation);
      state = state.copyWith(conversation: conversation);
    }
    state = state.copyWith(isGenerating: false, isSearching: false);
  }
}

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);

/// Rebuilds only when a conversation is created/saved (its [updatedAt]
/// changes) — not on every streamed token, which previously re-read the
/// entire Hive box dozens of times per second.
final conversationsProvider = Provider<List<Conversation>>((ref) {
  ref.watch(
    chatControllerProvider.select((s) => s.conversation?.updatedAt),
  );
  return StorageService.instance.getConversations();
});

final documentsProvider = Provider<List<DocumentItem>>((ref) {
  return StorageService.instance.getDocuments();
});

// Helper for debugging - call KnowledgeService.debugIndex() to see all chunks
