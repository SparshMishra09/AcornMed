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
    /// 1–10: answer quality / medical accuracy.
    required this.quality,
    /// 1–10: reliability at the app's "tool use" — following the [SEARCH:]
    /// directive, grounding on web/RAG context, and staying on-task.
    required this.toolCalling,
  });

  final String id;
  final String name;
  final String description;
  final String fileName;
  final String url;
  final int sizeBytes;
  final int quality;
  final int toolCalling;

  String get sizeLabel =>
      '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class ModelCatalog {
  ModelCatalog._();

  static const List<ModelOption> options = [
    ModelOption(
      id: 'smollm2-1.7b-q4',
      name: 'SmolLM2 1.7B Instruct',
      description:
          'Tiny and very fast — best for older or low-RAM phones. Great for '
          'quick definitions and lookups.',
      fileName: 'smollm2-1.7b-instruct-q4_k_m.gguf',
      url:
          'https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF/resolve/main/smollm2-1.7b-instruct-q4_k_m.gguf',
      sizeBytes: 1055609536,
      quality: 4,
      toolCalling: 4,
    ),
    ModelOption(
      id: 'qwen2.5-1.5b-q4',
      name: 'Qwen2.5 1.5B Instruct',
      description: 'Light and fast. Comfortable on most phones (~1 GB RAM).',
      fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      sizeBytes: 986000000,
      quality: 5,
      toolCalling: 5,
    ),
    ModelOption(
      id: 'llama3.2-3b-q4',
      name: 'Llama 3.2 3B Instruct',
      description:
          'Meta\'s compact model — fast and well-rounded for everyday study '
          'questions. Needs ~2 GB RAM.',
      fileName: 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      url:
          'https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      sizeBytes: 2019377600,
      quality: 6,
      toolCalling: 7,
    ),
    ModelOption(
      id: 'qwen2.5-3b-q4',
      name: 'Qwen2.5 3B Instruct',
      description:
          'Best balance of smarts and speed. Needs ~2.5 GB RAM. Recommended.',
      fileName: 'qwen2.5-3b-instruct-q4_k_m.gguf',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf',
      sizeBytes: 1929937120,
      quality: 7,
      toolCalling: 8,
    ),
    ModelOption(
      id: 'gemma3-4b-q4',
      name: 'Gemma 3 4B IT',
      description:
          'Google\'s Gemma 3 — strong factual recall, good for definitions, '
          'concepts, and study notes. Needs ~2.5 GB RAM.',
      fileName: 'gemma-3-4b-it-Q4_K_M.gguf',
      url:
          'https://huggingface.co/unsloth/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf',
      sizeBytes: 2489894016,
      quality: 7,
      toolCalling: 7,
    ),
    ModelOption(
      id: 'phi4-mini-q4',
      name: 'Phi-4 mini (3.8B)',
      description:
          'Microsoft\'s Phi-4 mini — excellent reasoning for clear, '
          'step-by-step explanations. Needs ~2.5 GB RAM.',
      fileName: 'Phi-4-mini-instruct-Q4_K_M.gguf',
      url:
          'https://huggingface.co/unsloth/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf',
      sizeBytes: 2491874272,
      quality: 8,
      toolCalling: 9,
    ),
    ModelOption(
      id: 'qwen2.5-7b-q4',
      name: 'Qwen2.5 7B Instruct',
      description:
          'Highest quality here — the smartest option, but needs ~5 GB RAM and '
          'a modern phone. Slower than the smaller models.',
      fileName: 'Qwen2.5-7B-Instruct-Q4_K_M.gguf',
      url:
          'https://huggingface.co/lmstudio-community/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf',
      sizeBytes: 4683073952,
      quality: 9,
      toolCalling: 8,
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
        .where((f) => f.path.toLowerCase().endsWith('.gguf'))
        .toList();
    if (entries.isEmpty) return null;
    DateTime modified(File f) {
      try {
        return f.lastModifiedSync();
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    entries.sort((a, b) => modified(b).compareTo(modified(a)));
    return entries.first;
  }

  Future<List<File>> listModelFiles() async {
    final dir = await _modelDir;
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.gguf'))
        .toList();
  }

  Future<void> deleteModelFile(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> importModelFile(String sourcePath) async {
    final source = File(sourcePath);
    final name = source.uri.pathSegments.last;
    if (!name.toLowerCase().endsWith('.gguf')) {
      throw const FormatException(
        'Only .gguf model files are supported.',
      );
    }
    final length = await source.length();
    if (length < 1024 * 1024) {
      throw const FormatException(
        'This file is too small to be a valid model.',
      );
    }
    final dir = await _modelDir;
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
    var sinkClosed = false;

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
      sinkClosed = true;
      await partial.rename(target.path);
      yield DownloadProgress(
        receivedBytes: received,
        totalBytes: totalBytes,
        isDone: true,
      );
    } catch (e) {
      if (!sinkClosed) {
        try {
          await sink.close();
        } catch (_) {}
      }
      // A user-initiated cancel surfaces as a client-closed error — treat
      // any failure while cancelling as a silent stop, not an error.
      if (e is _DownloadCancelled || _cancelling) {
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
