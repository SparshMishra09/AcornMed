import 'package:hive/hive.dart';

import 'web_source.dart';

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isError = false,
    this.sources = const [],
    this.imagePath,
    this.ocrText,
    this.webSearched = false,
  });

  final String id;
  final String role;
  String content;
  final DateTime timestamp;
  bool isError;
  List<WebSource> sources;
  String? imagePath;
  String? ocrText;
  bool webSearched;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
}

class ChatMessageAdapter extends TypeAdapter<ChatMessage> {
  @override
  final int typeId = 0;

  @override
  ChatMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatMessage(
      id: fields[0] as String,
      role: fields[1] as String,
      content: fields[2] as String,
      timestamp: fields[3] as DateTime,
      isError: fields[4] as bool? ?? false,
      sources: (fields[5] as List?)?.cast<WebSource>() ?? const [],
      imagePath: fields[6] as String?,
      ocrText: fields[7] as String?,
      webSearched: fields[8] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.role)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(3)
      ..write(obj.timestamp)
      ..writeByte(4)
      ..write(obj.isError)
      ..writeByte(5)
      ..write(obj.sources)
      ..writeByte(6)
      ..write(obj.imagePath)
      ..writeByte(7)
      ..write(obj.ocrText)
      ..writeByte(8)
      ..write(obj.webSearched);
  }
}
