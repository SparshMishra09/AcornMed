import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart' as llama;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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
        modelError: 'Could not load the model: $e',
      );
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
    await StorageService.instance.deleteConversation(id);
    if (state.conversation?.id == id) {
      state = const ChatState();
      await init();
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
    await StorageService.instance.saveConversation(conversation);
    state = state.copyWith(conversation: conversation);
  }

  Future<void> attachImage({required ImageSource source}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) return;

    final appDir = await getApplicationSupportDirectory();
    final imagesDir = Directory('${appDir.path}/images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    final ext = picked.path.split('.').last.toLowerCase();
    final target = File('${imagesDir.path}/${_uuid.v4()}.$ext');
    await File(picked.path).copy(target.path);

    state = state.copyWith(
      pendingImagePath: target.path,
      ocrLoading: true,
      clearOcrError: true,
      clearPendingOcr: true,
    );

    try {
      final text = await OcrService.instance.recognizeText(target.path);
      state = state.copyWith(
        ocrLoading: false,
        pendingOcrText: text.isEmpty ? null : text,
      );
    } catch (e) {
      state = state.copyWith(
        ocrLoading: false,
        ocrError: 'Could not read text from the image: $e',
      );
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
    ];
    if (triggers.any(lower.contains)) return true;
    final year = DateTime.now().year;
    return RegExp('\\b($year|${year - 1})\\b').hasMatch(lower);
  }

  Future<void> sendMessage(String text, {bool webSearch = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isGenerating || state.isSearching) return;

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

    final assistantMessage = ChatMessage(
      id: _uuid.v4(),
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
    );
    conversation.messages.add(assistantMessage);

    final imagePath = state.pendingImagePath;
    final ocrText = state.pendingOcrText;
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
    );
  }

  Future<void> _generate({
    required Conversation conversation,
    required ChatMessage assistantMessage,
    required String userText,
    String? ocrText,
    bool hasImage = false,
    List<WebSearchResult>? searchResults,
    required bool allowSearchIntercept,
  }) async {
    final engine = AiEngine.instance;

    // DEBUG: Log attached document IDs
    if (conversation.attachedDocIds.isNotEmpty) {
      debugLog('📎 ${conversation.attachedDocIds.length} document(s) attached: ${conversation.attachedDocIds.join(", ")}');
    }

    final ragContext = KnowledgeService.instance.buildContext(
      userText,
      attachedDocIds: conversation.attachedDocIds,
    );
    
    // Show context length in debug mode
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
    }

    final history = conversation.messages
        .where((m) => m.id != assistantMessage.id && m.content.isNotEmpty)
        .toList();

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

    final detector = _SearchDirectiveDetector();
    var flushed = false;

    try {
      final stream = engine.chat(messages: llamaMessages);
      final completer = Completer<void>();
      _tokenSub = stream.listen(
        (token) {
          if (flushed) {
            assistantMessage.content += token;
            state = state.copyWith(conversation: conversation);
            return;
          }
          detector.add(token);
          if (detector.isFailed) {
            assistantMessage.content += detector.buffered;
            flushed = true;
            state = state.copyWith(conversation: conversation);
          }
        },
        onError: (Object e) {
          if (assistantMessage.content.isEmpty && !detector.isComplete) {
            assistantMessage.content =
                'Something went wrong while generating. Please try again.';
            assistantMessage.isError = true;
          }
          _finalize(conversation);
          state = state.copyWith(conversation: conversation, isGenerating: false);
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!flushed && !detector.isComplete) {
            assistantMessage.content += detector.buffered;
          }
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      await completer.future;
    } catch (e) {
      assistantMessage.content = 'Could not start generation: $e';
      assistantMessage.isError = true;
      state = state.copyWith(conversation: conversation, isGenerating: false);
      return;
    }

    if (!flushed && detector.isComplete && allowSearchIntercept) {
      final query = detector.query!;
      assistantMessage.content = '';
      state = state.copyWith(isSearching: true, isGenerating: false);
      final results = await WebSearchService.instance.search(query);
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
        );
        return;
      }
      assistantMessage.content =
          'I tried to search the web for "$query" but got no results. '
          'Please try rephrasing your question.';
      assistantMessage.isError = true;
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

    _finalize(conversation);
    state = state.copyWith(conversation: conversation, isGenerating: false);
  }

  void _finalize(Conversation conversation) {
    conversation.updatedAt = DateTime.now();
    StorageService.instance.saveConversation(conversation);
  }

  Future<void> stopGenerating() async {
    await AiEngine.instance.stop();
    await _tokenSub?.cancel();
    _tokenSub = null;
    final conversation = state.conversation;
    if (conversation != null) {
      conversation.updatedAt = DateTime.now();
      await StorageService.instance.saveConversation(conversation);
    }
    state = state.copyWith(isGenerating: false, isSearching: false);
  }
}

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);

final conversationsProvider = Provider<List<Conversation>>((ref) {
  ref.watch(chatControllerProvider);
  return StorageService.instance.getConversations();
});

final documentsProvider = Provider<List<DocumentItem>>((ref) {
  return StorageService.instance.getDocuments();
});

// Helper for debugging - call KnowledgeService.debugIndex() to see all chunks
