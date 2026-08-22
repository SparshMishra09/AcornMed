import 'package:hive/hive.dart';

class DocumentItem {
  DocumentItem({
    required this.id,
    required this.name,
    required this.filePath,
    required this.addedAt,
    required this.charCount,
    this.pageCount,
  });

  final String id;
  final String name;
  final String filePath;
  final DateTime addedAt;
  final int charCount;
  final int? pageCount;

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
  }
}

class DocumentItemAdapter extends TypeAdapter<DocumentItem> {
  @override
  final int typeId = 3;

  @override
  DocumentItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DocumentItem(
      id: fields[0] as String,
      name: fields[1] as String,
      filePath: fields[2] as String,
      addedAt: fields[3] as DateTime,
      charCount: fields[4] as int,
      pageCount: fields[5] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, DocumentItem obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.filePath)
      ..writeByte(3)
      ..write(obj.addedAt)
      ..writeByte(4)
      ..write(obj.charCount)
      ..writeByte(5)
      ..write(obj.pageCount);
  }
}
