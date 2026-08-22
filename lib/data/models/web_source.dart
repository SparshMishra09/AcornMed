import 'package:hive/hive.dart';

class WebSource {
  const WebSource({
    required this.title,
    required this.url,
    required this.source,
    this.date,
  });

  final String title;
  final String url;
  final String source;
  final String? date;
}

class WebSourceAdapter extends TypeAdapter<WebSource> {
  @override
  final int typeId = 2;

  @override
  WebSource read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WebSource(
      title: fields[0] as String,
      url: fields[1] as String,
      source: fields[2] as String,
      date: fields[3] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, WebSource obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.title)
      ..writeByte(1)
      ..write(obj.url)
      ..writeByte(2)
      ..write(obj.source)
      ..writeByte(3)
      ..write(obj.date);
  }
}
