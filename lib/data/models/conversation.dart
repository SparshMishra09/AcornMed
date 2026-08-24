import 'package:hive/hive.dart';

import 'chat_message.dart';

class Conversation {
  Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    List<ChatMessage>? messages,
    List<String>? attachedDocIds,
  })  : messages = messages ?? [],
        attachedDocIds = attachedDocIds ?? [];

  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  List<ChatMessage> messages;
  List<String> attachedDocIds;
}

class ConversationAdapter extends TypeAdapter<Conversation> {
  @override
  final int typeId = 1;

  @override
  Conversation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Conversation(
      id: fields[0] as String,
      title: (fields[1] as String?) ?? 'Chat',
      createdAt: fields[2] as DateTime,
      updatedAt: fields[3] as DateTime,
      // Defensive casts keep old/partial boxes from crashing on read.
      messages: (fields[4] as List?)?.cast<ChatMessage>() ?? [],
      attachedDocIds: (fields[5] as List?)?.cast<String>() ?? [],
    );
  }

  @override
  void write(BinaryWriter writer, Conversation obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.updatedAt)
      ..writeByte(4)
      ..write(obj.messages)
      ..writeByte(5)
      ..write(obj.attachedDocIds);
  }
}
