import 'package:hive_flutter/hive_flutter.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/document_item.dart';
import '../models/web_source.dart';

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const String _conversationsBox = 'conversations';
  static const String _documentsBox = 'documents';

  late Box<Conversation> _box;
  late Box<DocumentItem> _docsBox;

  Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ConversationAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(WebSourceAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(DocumentItemAdapter());
    }
    _box = await Hive.openBox<Conversation>(_conversationsBox);
    _docsBox = await Hive.openBox<DocumentItem>(_documentsBox);
  }

  List<Conversation> getConversations() {
    final list = _box.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Conversation? getConversation(String id) => _box.get(id);

  Future<void> saveConversation(Conversation conversation) =>
      _box.put(conversation.id, conversation);

  Future<void> deleteConversation(String id) => _box.delete(id);

  Future<void> clearAll() => _box.clear();

  List<DocumentItem> getDocuments() {
    final list = _docsBox.values.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }

  DocumentItem? getDocument(String id) => _docsBox.get(id);

  Future<void> saveDocument(DocumentItem document) =>
      _docsBox.put(document.id, document);

  Future<void> deleteDocument(String id) => _docsBox.delete(id);
}
