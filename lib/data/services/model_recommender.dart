import 'dart:io';

import 'package:llama_flutter_android/llama_flutter_android.dart'
    as llama;
import 'model_manager.dart';

/// A snapshot of the device's inference capacity, used to pick a model that is
/// smart enough, reliable at tool use (web search / RAG), and fast enough that
/// the user doesn't lose interest while it streams.
class DeviceProfile {
  DeviceProfile({
    required this.totalRamBytes,
    required this.freeRamBytes,
    required this.vulkanSupported,
    required this.gpuName,
    required this.recommendedGpuLayers,
    required this.cores,
  });

  final int totalRamBytes;
  final int freeRamBytes;
  final bool vulkanSupported;
  final String gpuName;
  final int recommendedGpuLayers;
  final int cores;

  /// Probes the device once. Cheap: creates a throwaway [LlamaController],
  /// asks the native layer for GPU/RAM info, then disposes it. Never throws —
  /// on failure it returns a conservative CPU-only profile so the app can
  /// still show every model and let the user decide.
  static Future<DeviceProfile> detect() async {
    final fallback = DeviceProfile(
      totalRamBytes: 3 * 1024 * 1024 * 1024,
      freeRamBytes: 1 * 1024 * 1024 * 1024,
      vulkanSupported: false,
      gpuName: 'unknown',
      recommendedGpuLayers: 0,
      cores: 4,
    );
    try {
      final controller = llama.LlamaController();
      final gpu = await controller.detectGpu();
      await controller.dispose();
      return DeviceProfile(
        totalRamBytes: gpu.deviceLocalMemoryBytes,
        freeRamBytes: gpu.freeRamBytes,
        vulkanSupported: gpu.vulkanSupported,
        gpuName: gpu.gpuName,
        recommendedGpuLayers: gpu.recommendedGpuLayers,
        cores: Platform.numberOfProcessors,
      );
    } catch (_) {
      return fallback;
    }
  }
}

/// The scored result for one candidate model on this device.
class ModelFit {
  ModelFit({
    required this.option,
    required this.fit,
    required this.speedScore,
    required this.qualityScore,
    required this.toolScore,
    required this.feasible,
    required this.reason,
  });

  final ModelOption option;
  /// 0–100 overall recommendation score.
  final double fit;
  final double speedScore;
  final double qualityScore;
  final double toolScore;
  final bool feasible;
  final String reason;
}

/// Ranks [options] for [profile] and returns them best-first.
///
/// The score blends three pillars the user cares about:
///   • speed  (40%) — estimated tokens/sec, boosted when the GPU can offload
///   • quality (35%) — answer accuracy / medical helpfulness
///   • tool   (25%) — reliability at [SEARCH:] + RAG grounding
///
/// Models that can't fit in RAM are dropped first, so we never recommend
/// something that would crash or thrash.
List<ModelFit> rankModels(
  List<ModelOption> options,
  DeviceProfile profile,
) {
  final ranked = <ModelFit>[];
  for (final option in options) {
    ranked.add(_score(option, profile));
  }
  ranked.sort((a, b) => b.fit.compareTo(a.fit));
  return ranked;
}

ModelFit _score(ModelOption option, DeviceProfile profile) {
  final sizeGB = option.sizeBytes / 1e9;
  // Rough tokens/sec estimate for CPU inference on this class of phone.
  final cpuTps = (40 / sizeGB).clamp(3.0, 45.0);
  var factor = 1.0;
  if (profile.vulkanSupported) {
    if (profile.recommendedGpuLayers >= 99) {
      factor = 3.5; // Full GPU offload.
    } else if (profile.recommendedGpuLayers >= 16) {
      factor = 2.0; // Partial offload.
    }
  }
  final estTps = cpuTps * factor;
  final speedScore = (estTps / 40 * 100).clamp(0.0, 100.0);

  final qualityScore = option.quality * 10.0; // 0–100
  final toolScore = option.toolCalling * 10.0; // 0–100

  // RAM gate: a model needs ~1.3x its size for weights + KV cache, plus
  // headroom so the OS and other apps don't get squeezed.
  final ramNeededMB = option.sizeBytes / (1024 * 1024) * 1.3 + 600;
  final totalRamMB = profile.totalRamBytes / (1024 * 1024);
  final feasible = ramNeededMB <= totalRamMB * 0.85;

  // Infeasible models get a strongly negative score so they sink to the
  // bottom regardless of their other merits.
  final fit = feasible
      ? (0.40 * speedScore + 0.35 * qualityScore + 0.25 * toolScore)
      : -1.0;

  return ModelFit(
    option: option,
    fit: fit,
    speedScore: speedScore,
    qualityScore: qualityScore,
    toolScore: toolScore,
    feasible: feasible,
    reason: _reason(option, profile, feasible, estTps),
  );
}

String _reason(
  ModelOption option,
  DeviceProfile profile,
  bool feasible,
  double estTps,
) {
  final ramGB = (profile.totalRamBytes / 1e9).toStringAsFixed(0);
  final gpuText = profile.vulkanSupported
      ? 'a Vulkan GPU (${profile.gpuName})'
      : 'no discrete GPU (CPU only)';
  if (!feasible) {
    return '${option.name} needs more RAM than your device\'s ~$ramGB GB. '
        'Pick a smaller model below.';
  }
  final speedWord = estTps >= 25
      ? 'very fast'
      : estTps >= 12
          ? 'fast'
          : 'steady';
  return 'Your device has ~$ramGB GB RAM and $gpuText. ${option.name} is the '
      'best fit: $speedWord replies (≈${estTps.round()} tok/s est.), smart '
      'enough for accurate answers, and reliable at using web search and your '
      'documents.';
}
