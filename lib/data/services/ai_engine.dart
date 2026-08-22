import 'dart:async';
import 'dart:io';

import 'package:llama_flutter_android/llama_flutter_android.dart' as llama;

const String kMedicalSystemPrompt = '''
You are AcornMed, a warm, knowledgeable, and precise AI study assistant for medical students. You run entirely on the student's device — private and offline.

Guidelines:
- Answer medical questions clearly and accurately, at a medical-student level (anatomy, physiology, pharmacology, pathology, biochemistry, microbiology, clinical medicine).
- Structure answers well: use short headings, bullet points, and tables in markdown when they help.
- Explain mechanisms step by step. Give classic exam-relevant points, mnemonics, and high-yield facts when useful.
- For differential diagnoses, list the most likely causes first with brief distinguishing features.
- For drugs, cover class, mechanism, key uses, adverse effects, and contraindications concisely.
- If a question is ambiguous, state your assumption briefly and answer.
- If you are unsure or the topic is beyond reliable knowledge, say so honestly. Never invent citations, studies, or statistics.
- You are a study aid, not a doctor. For anything resembling personal medical advice, remind the student to consult qualified professionals and standard references.
- Keep answers focused and reasonably concise unless the student asks for depth.

Web search protocol:
- If the question needs up-to-date information you do not reliably have (latest guidelines, recent studies, drug approvals, current recommendations, news, or anything after your training cutoff), reply with ONLY this single line and nothing else:
[SEARCH: a concise search query]
- The app will then run the search and ask you again with live results — answer from those results, prefer the most recent sources, and cite them by number.
- Do NOT use [SEARCH:] for standard medical knowledge you already know well.
''';

enum EngineStatus { idle, loading, ready, generating, error }

class AiEngine {
  AiEngine._();
  static final AiEngine instance = AiEngine._();

  llama.LlamaController? _controller;
  EngineStatus status = EngineStatus.idle;
  String? lastError;
  String? loadedModelPath;

  final _statusController = StreamController<EngineStatus>.broadcast();
  Stream<EngineStatus> get statusStream => _statusController.stream;

  void _setStatus(EngineStatus s) {
    status = s;
    _statusController.add(s);
  }

  bool get isReady => status == EngineStatus.ready;

  Future<void> loadModel(
    File modelFile, {
    int threads = 4,
    int contextSize = 4096,
    int? gpuLayers,
  }) async {
    if (status == EngineStatus.loading) return;
    _setStatus(EngineStatus.loading);
    lastError = null;
    try {
      _controller ??= llama.LlamaController();
      final alreadyLoaded = await _controller!.isModelLoaded();
      if (alreadyLoaded && loadedModelPath == modelFile.path) {
        _setStatus(EngineStatus.ready);
        return;
      }
      if (alreadyLoaded) {
        await _controller!.dispose();
        _controller = llama.LlamaController();
      }
      await _controller!.loadModel(
        modelPath: modelFile.path,
        threads: threads,
        contextSize: contextSize,
        gpuLayers: gpuLayers,
      );
      loadedModelPath = modelFile.path;
      _setStatus(EngineStatus.ready);
    } catch (e) {
      lastError = e.toString();
      _setStatus(EngineStatus.error);
      rethrow;
    }
  }

  Stream<String> chat({
    required List<llama.ChatMessage> messages,
    int maxTokens = 1024,
    double temperature = 0.5,
  }) {
    final controller = _controller;
    if (controller == null || status != EngineStatus.ready) {
      throw StateError('Model is not loaded');
    }
    _setStatus(EngineStatus.generating);
    final stream = controller.generateChat(
      messages: messages,
      maxTokens: maxTokens,
      temperature: temperature,
      topP: 0.9,
      topK: 40,
      minP: 0.05,
      repeatPenalty: 1.1,
    );
    final relay = StreamController<String>();
    stream.listen(
      relay.add,
      onError: relay.addError,
      onDone: () {
        if (status == EngineStatus.generating) {
          _setStatus(EngineStatus.ready);
        }
        relay.close();
      },
    );
    return relay.stream;
  }

  Future<void> stop() async {
    await _controller?.stop();
    if (status == EngineStatus.generating) {
      _setStatus(EngineStatus.ready);
    }
  }

  Future<void> clearContext() async {
    await _controller?.clearContext();
  }

  Future<void> unload() async {
    await stop();
    await _controller?.dispose();
    _controller = null;
    loadedModelPath = null;
    _setStatus(EngineStatus.idle);
  }
}
