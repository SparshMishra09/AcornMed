import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/friendly_error.dart';
import '../../data/services/model_manager.dart';
import '../../data/services/model_recommender.dart';
import '../../providers/chat_providers.dart';

class ModelSetupScreen extends ConsumerStatefulWidget {
  const ModelSetupScreen({super.key});

  @override
  ConsumerState<ModelSetupScreen> createState() => _ModelSetupScreenState();
}

class _ModelSetupScreenState extends ConsumerState<ModelSetupScreen> {
  ModelOption? _downloading;
  DownloadProgress? _progress;
  StreamSubscription<DownloadProgress>? _sub;
  bool _importing = false;
  List<File> _installed = [];
  List<ModelFit> _ranked = [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _refreshInstalled();
    _scanDevice();
  }

  /// Probes the device once and ranks every catalog model by how well it fits
  /// (smart + tool-capable + fast). Failures just leave the list unranked so
  /// the user can still pick manually.
  Future<void> _scanDevice() async {
    if (!mounted) return;
    setState(() => _scanning = true);
    try {
      final profile = await DeviceProfile.detect();
      final ranked = rankModels(ModelCatalog.options, profile);
      if (!mounted) return;
      setState(() {
        _ranked = ranked;
        _scanning = false;
      });
    } catch (_) {
      if (mounted) setState(() => _scanning = false);
    }
  }

  ModelFit? get _best {
    if (_ranked.isEmpty) return null;
    final top = _ranked.first;
    return top.feasible ? top : null;
  }

  Future<void> _useRecommended(ModelFit fit) async {
    final installed =
        _installed.any((f) => f.path.endsWith(fit.option.fileName));
    if (installed) {
      await _finishWithFile(fit.option.fileName);
    } else {
      _startDownload(fit.option);
    }
  }

  Future<void> _refreshInstalled() async {
    final files = await ModelManager.instance.listModelFiles();
    if (!mounted) return;
    setState(() => _installed = files);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _startDownload(ModelOption option) {
    if (_downloading != null) return; // One download at a time.
    setState(() {
      _downloading = option;
      _progress = null;
    });
    _sub = ModelManager.instance.downloadModel(option).listen(
      (progress) {
        if (!mounted) return;
        setState(() => _progress = progress);
        if (progress.isDone) {
          _sub?.cancel();
          _sub = null;
          _finishWithFile(option.fileName);
        }
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _downloading = null;
          _progress = null;
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(_downloadErrorText(e)),
              duration: const Duration(seconds: 5),
            ),
          );
      },
      onDone: () {
        if (_downloading != null && _progress?.isDone != true) {
          if (mounted) {
            setState(() {
              _downloading = null;
              _progress = null;
            });
          }
        }
      },
    );
  }

  /// Downloads are resumable (the .part file is kept), so every failure
  /// message reassures the user and points at the same Download button.
  String _downloadErrorText(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('connection closed') ||
        s.contains('socket') ||
        s.contains('clientexception') ||
        s.contains('failed host lookup') ||
        s.contains('connection refused')) {
      return 'The connection dropped — your progress is saved. '
          'Tap Download to pick up where it left off.';
    }
    if (s.contains('timeout')) {
      return 'The download timed out — your progress is saved. '
          'Tap Download to resume.';
    }
    if (s.contains('http')) {
      return 'The model server is having trouble right now. '
          'Please try again in a little while.';
    }
    return friendlyError(e);
  }

  Future<void> _finishWithFile(String fileName) async {
    final file = await ModelManager.instance.findModelFile(fileName);
    if (file == null || !mounted) return;
    await ref.read(chatControllerProvider.notifier).setModelFile(file);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Model ready! You can chat now.')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _importFile() async {
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Importing model…')),
      );
      final file = await ModelManager.instance.importModelFile(path);
      await _refreshInstalled();
      if (!mounted) return;
      await ref.read(chatControllerProvider.notifier).setModelFile(file);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Model imported and ready!')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is FormatException
                ? e.message
                : 'Couldn\'t import this file. Make sure it\'s a valid '
                    '.gguf model and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _confirmDeleteModel(File file) async {
    final activeFile = ref.read(chatControllerProvider).modelFile;
    final isActive = activeFile != null && activeFile.path == file.path;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete model?'),
          content: Text(
            '${file.uri.pathSegments.last} will be permanently removed from '
            'this device.'
            '${isActive ? '\n\nThis is your active model — the app will '
                'need to set one up again before you can chat.' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (isActive) {
      // Unload first — deleting an mmap'd model file while the engine is
      // running is undefined behaviour.
      await ref.read(chatControllerProvider.notifier).unloadActiveModel();
    }
    await ModelManager.instance.deleteModelFile(file);
    await _refreshInstalled();
  }

  String _formatBytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Model setup')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Choose a model',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.coffee,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Downloaded once from HuggingFace (open weights, no account). '
            'Stored privately on your device — works offline forever after.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.coffee.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 16),
          if (_scanning || _best != null) ...[
            _RecommendationBanner(
              scanning: _scanning,
              best: _best,
              onUse: _best != null ? () => _useRecommended(_best!) : null,
            ),
            const SizedBox(height: 16),
          ],
          for (final option in ModelCatalog.options)
            _ModelCard(
              option: option,
              isDownloading: _downloading?.id == option.id,
              progress: _downloading?.id == option.id ? _progress : null,
              isInstalled: _installed.any((f) => f.path.endsWith(option.fileName)),
              recommended: _best?.option.id == option.id,
              fit: _best?.option.id == option.id ? _best : null,
              onDownload: () => _startDownload(option),
              onCancel: () {
                ModelManager.instance.cancelDownload();
                _sub?.cancel();
                _sub = null;
                setState(() {
                  _downloading = null;
                  _progress = null;
                });
              },
              onUse: () => _finishWithFile(option.fileName),
            ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'Bring your own model',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.coffee,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'For maximum privacy, import any .gguf chat model from your '
            'storage (e.g. transferred via USB or adb push).',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.coffee.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _importing ? null : _importFile,
            icon: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open_rounded),
            label: Text(_importing ? 'Importing…' : 'Import .gguf file'),
          ),
          if (_installed.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'Installed models',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.coffee,
              ),
            ),
            const SizedBox(height: 10),
            for (final file in _installed)
              _InstalledTile(
                file: file,
                formatBytes: _formatBytes,
                onDelete: () => _confirmDeleteModel(file),
              ),
          ],
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.option,
    required this.isDownloading,
    required this.progress,
    required this.isInstalled,
    this.recommended = false,
    this.fit,
    required this.onDownload,
    required this.onCancel,
    required this.onUse,
  });

  final ModelOption option;
  final bool isDownloading;
  final DownloadProgress? progress;
  final bool isInstalled;
  final bool recommended;
  final ModelFit? fit;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: recommended
              ? AppColors.sageDark
              : isDownloading
                  ? AppColors.mustard
                  : AppColors.outlineSoft,
          width: recommended || isDownloading ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recommended) ...[
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    size: 14, color: AppColors.sageDark),
                const SizedBox(width: 6),
                const Text(
                  'BEST FOR YOUR DEVICE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.sageDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  option.name,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.coffee,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.sageLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  option.sizeLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.sageDeep,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            option.description,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.coffee.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: option.supportsVision
                  ? AppColors.sageLight
                  : AppColors.coffee.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  option.supportsVision
                      ? Icons.photo_camera_rounded
                      : Icons.text_fields_rounded,
                  size: 13,
                  color: option.supportsVision
                      ? AppColors.sageDark
                      : AppColors.coffeeSoft,
                ),
                const SizedBox(width: 5),
                Text(
                  option.supportsVision
                      ? 'Supports images'
                      : 'Text only — images via OCR',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: option.supportsVision
                        ? AppColors.sageDark
                        : AppColors.coffeeSoft,
                  ),
                ),
              ],
            ),
          ),
          if (recommended && fit != null) ...[
            const SizedBox(height: 12),
            _PillarMeter(
                label: 'Smart', value: fit!.qualityScore, icon: Icons.psychology),
            const SizedBox(height: 6),
            _PillarMeter(
                label: 'Tool-ready',
                value: fit!.toolScore,
                icon: Icons.build_circle_outlined),
            const SizedBox(height: 6),
            _PillarMeter(
                label: 'Fast', value: fit!.speedScore, icon: Icons.flash_on),
          ],
          const SizedBox(height: 14),
          if (isDownloading && progress != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress!.fraction,
                minHeight: 8,
                backgroundColor: AppColors.sageLight,
                color: AppColors.mustard,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${(progress!.fraction * 100).toStringAsFixed(0)}% · '
                  '${_fmt(progress!.receivedBytes)} / ${_fmt(progress!.totalBytes)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.coffeeSoft,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ] else if (isDownloading) ...[
            const LinearProgressIndicator(minHeight: 8),
            const SizedBox(height: 8),
            const Text(
              'Starting download…',
              style: TextStyle(fontSize: 12, color: AppColors.coffeeSoft),
            ),
          ] else if (isInstalled)
            FilledButton.icon(
              onPressed: onUse,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Use this model'),
            )
          else
            FilledButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Download'),
            ),
        ],
      ),
    );
  }

  String _fmt(int bytes) {
    final mb = bytes / (1024 * 1024);
    return mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(2)} GB'
        : '${mb.toStringAsFixed(0)} MB';
  }
}

class _RecommendationBanner extends StatelessWidget {
  const _RecommendationBanner({
    required this.scanning,
    required this.best,
    required this.onUse,
  });

  final bool scanning;
  final ModelFit? best;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    if (scanning) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.sageLight,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text(
              'Checking your device for the best model…',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.sageDeep,
              ),
            ),
          ],
        ),
      );
    }
    if (best == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.sageDark, AppColors.sageDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'RECOMMENDED FOR YOUR DEVICE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  best!.option.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  best!.option.sizeLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            best!.reason,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onUse,
              icon: const Icon(Icons.rocket_launch_rounded),
              label: const Text('Use this model'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.sageDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillarMeter extends StatelessWidget {
  const _PillarMeter({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final double value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final pct = value.clamp(0.0, 100.0);
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.sageDeep),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.coffee,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 6,
              backgroundColor: AppColors.sageLight,
              color: AppColors.sageDark,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${pct.round()}',
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.coffeeSoft,
          ),
        ),
      ],
    );
  }
}

class _InstalledTile extends StatelessWidget {
  const _InstalledTile({
    required this.file,
    required this.formatBytes,
    required this.onDelete,
  });

  final File file;
  final String Function(int) formatBytes;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final name = file.uri.pathSegments.last;
    return FutureBuilder<int>(
      future: file.length(),
      builder: (context, snapshot) {
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description_outlined),
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5),
          ),
          subtitle: Text(
            snapshot.hasData ? formatBytes(snapshot.data!) : '…',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.error,
            ),
            onPressed: () => onDelete(),
          ),
        );
      },
    );
  }
}
