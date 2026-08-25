import 'package:shared_preferences/shared_preferences.dart';

import '../../data/services/ai_engine.dart';
import '../../data/services/knowledge_service.dart';

const String _kFastMode = 'fastMode';

/// Reads the saved "Faster responses" preference.
Future<bool> loadFastMode() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kFastMode) ?? false;
}

/// Persists the preference and immediately applies it to the running engine
/// and knowledge index.
Future<void> setFastMode(bool fast) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kFastMode, fast);
  applyFastModeNow(fast);
}

/// Applies the performance profile without touching storage. Call this at
/// startup (after reading the saved value) so settings are in effect before
/// the first model load.
void applyFastModeNow(bool fast) {
  if (fast) {
    // Smaller context + shorter replies + less RAG injection. This shrinks
    // the prompt (faster first token) and the KV cache, and the decode of a
    // shorter answer finishes sooner.
    AiEngine.instance.contextSize = 2048;
    AiEngine.instance.maxTokens = 768;
    KnowledgeService.instance.maxContextChars = 3000;
    KnowledgeService.instance.maxDocContextChars = 3000;
  } else {
    AiEngine.instance.contextSize = 4096;
    AiEngine.instance.maxTokens = 1024;
    KnowledgeService.instance.maxContextChars = 6000;
    KnowledgeService.instance.maxDocContextChars = 6000;
  }
}
