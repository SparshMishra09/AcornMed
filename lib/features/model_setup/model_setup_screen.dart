import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/model_manager.dart';
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

  @override
  void initState() {
    super.initState();
    _refreshInstalled();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
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
        SnackBar(content: Text('Import failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
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
          for (final option in ModelCatalog.options)
            _ModelCard(
              option: option,
              isDownloading: _downloading?.id == option.id,
              progress: _downloading?.id == option.id ? _progress : null,
              isInstalled: _installed.any((f) => f.path.endsWith(option.fileName)),
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
                onDelete: () async {
                  await ModelManager.instance.deleteModelFile(file);
                  await _refreshInstalled();
                },
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
    required this.onDownload,
    required this.onCancel,
    required this.onUse,
  });

  final ModelOption option;
  final bool isDownloading;
  final DownloadProgress? progress;
  final bool isInstalled;
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
          color: isDownloading ? AppColors.mustard : AppColors.outlineSoft,
          width: isDownloading ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
