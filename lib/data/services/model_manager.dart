import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ModelOption {
  const ModelOption({
    required this.id,
    required this.name,
    required this.description,
    required this.fileName,
    required this.url,
    required this.sizeBytes,
  });

  final String id;
  final String name;
  final String description;
  final String fileName;
  final String url;
  final int sizeBytes;

  String get sizeLabel =>
      '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class ModelCatalog {
  ModelCatalog._();

  static const List<ModelOption> options = [
    ModelOption(
      id: 'qwen2.5-3b-q4',
      name: 'Qwen2.5 3B Instruct',
      description:
          'Best balance of smarts and speed. Needs ~2.5 GB RAM. Recommended.',
      fileName: 'qwen2.5-3b-instruct-q4_k_m.gguf',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf',
      sizeBytes: 1929937120,
    ),
    ModelOption(
      id: 'qwen2.5-1.5b-q4',
      name: 'Qwen2.5 1.5B Instruct',
      description: 'Lighter and faster. Works on older phones (~1.5 GB RAM).',
      fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      sizeBytes: 986000000,
    ),
  ];
}

class DownloadProgress {
  const DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.isDone,
  });

  final int receivedBytes;
  final int totalBytes;
  final bool isDone;

  double get fraction =>
      totalBytes <= 0 ? 0 : (receivedBytes / totalBytes).clamp(0.0, 1.0);
}

class ModelManager {
  ModelManager._();
  static final ModelManager instance = ModelManager._();

  static const String _modelDirName = 'models';

  http.Client? _client;
  bool _cancelling = false;

  Future<Directory> get _modelDir async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}/$_modelDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File?> findModelFile(String fileName) async {
    final dir = await _modelDir;
    final file = File('${dir.path}/$fileName');
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  Future<File?> getActiveModelFile() async {
    final dir = await _modelDir;
    final entries = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.gguf'))
        .toList();
    if (entries.isEmpty) return null;
    entries.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return entries.first;
  }

  Future<List<File>> listModelFiles() async {
    final dir = await _modelDir;
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.gguf'))
        .toList();
  }

  Future<void> deleteModelFile(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> importModelFile(String sourcePath) async {
    final dir = await _modelDir;
    final source = File(sourcePath);
    final name = source.uri.pathSegments.last;
    final target = File('${dir.path}/$name');
    if (await target.exists()) {
      await target.delete();
    }
    await source.copy(target.path);
    return target;
  }

  Stream<DownloadProgress> downloadModel(ModelOption option) async* {
    final dir = await _modelDir;
    final target = File('${dir.path}/${option.fileName}');
    final partial = File('${target.path}.part');

    var startByte = 0;
    if (await partial.exists()) {
      startByte = await partial.length();
    }
    if (await target.exists()) {
      final len = await target.length();
      if (len >= option.sizeBytes) {
        yield DownloadProgress(
          receivedBytes: len,
          totalBytes: option.sizeBytes,
          isDone: true,
        );
        return;
      }
    }

    _cancelling = false;
    _client = http.Client();
    final request = http.Request('GET', Uri.parse(option.url));
    if (startByte > 0) {
      request.headers['Range'] = 'bytes=$startByte-';
    }

    final response = await _client!.send(request);
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('Download failed (HTTP ${response.statusCode})');
    }

    final totalBytes = response.statusCode == 206
        ? startByte + (response.contentLength ?? 0)
        : (response.contentLength ?? option.sizeBytes);

    var received = startByte;
    final sink = partial.openWrite(mode: FileMode.append);

    try {
      await for (final chunk in response.stream) {
        if (_cancelling) {
          throw const _DownloadCancelled();
        }
        sink.add(chunk);
        received += chunk.length;
        yield DownloadProgress(
          receivedBytes: received,
          totalBytes: totalBytes,
          isDone: false,
        );
      }
      await sink.flush();
      await sink.close();
      await partial.rename(target.path);
      yield DownloadProgress(
        receivedBytes: received,
        totalBytes: totalBytes,
        isDone: true,
      );
    } catch (e) {
      await sink.close();
      if (e is _DownloadCancelled) {
        return;
      }
      rethrow;
    } finally {
      _client?.close();
      _client = null;
    }
  }

  void cancelDownload() {
    _cancelling = true;
    _client?.close();
  }
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}
