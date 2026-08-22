import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/web_source.dart';
import '../../providers/chat_providers.dart';
import 'attach_documents_sheet.dart';

const List<String> _quickPrompts = [
  'Explain the mechanism of action of aspirin',
  'Differential diagnosis for chest pain',
  'Summarize the brachial plexus',
  'High-yield facts about diabetes mellitus',
  'Compare nephrotic vs nephritic syndrome',
  'Mnemonics for cranial nerves',
];

class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key, required this.state});

  final ChatState state;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _webSearch = false;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    final messages = state.messages;
    
    // DEBUG: Show attached document info at top of chat
    final hasAttachments = state.attachedDocIds.isNotEmpty;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.isGenerating || state.isSearching || messages.length <= 1) {
        _scrollToBottom();
      }
    });

    return Column(
      children: [
        // DEBUG: Show attached document IDs (remove after debugging)
        if (hasAttachments && kDebugMode) ...[
          Container(
            padding: const EdgeInsets.all(8),
            color: AppColors.mustard.withValues(alpha: 0.3),
            child: Text(
              '📎 Attached: ${state.attachedDocIds.length} doc(s)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.sageDeep,
              ),
            ),
          ),
        ],
        Expanded(
          child: messages.isEmpty
              ? _EmptyState(onPromptTap: _send)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isLast = index == messages.length - 1;
                    return _MessageBubble(
                      message: message,
                      isStreaming: isLast && state.isGenerating,
                    );
                  },
                ),
        ),
        if (state.isSearching)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.mustard.withValues(alpha: 0.12),
            child: const Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.mustardDark,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'Searching the web for the latest information…',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mustardDark,
                  ),
                ),
              ],
            ),
          ),
        if (state.modelError != null)
          Container(
            width: double.infinity,
            color: AppColors.error.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              state.modelError!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
        if (state.pendingImagePath != null)
          _PendingImageBar(
            imagePath: state.pendingImagePath!,
            ocrLoading: state.ocrLoading,
            ocrText: state.pendingOcrText,
            ocrError: state.ocrError,
            onRemove: () =>
                ref.read(chatControllerProvider.notifier).clearPendingImage(),
          ),
        _InputBar(
          controller: _inputController,
          isGenerating: state.isGenerating,
          isSearching: state.isSearching,
          modelLoading: state.modelLoading,
          webSearch: _webSearch,
          onToggleWeb: () => setState(() => _webSearch = !_webSearch),
          onSend: _send,
          onStop: () =>
              ref.read(chatControllerProvider.notifier).stopGenerating(),
          onAttachImage: () => _showImageOptions(context),
          onAttachDocument: () => _showDocumentSheet(context),
          attachedDocCount: state.attachedDocIds.length,
        ),
      ],
    );
  }

  void _send(String text) {
    _inputController.clear();
    ref
        .read(chatControllerProvider.notifier)
        .sendMessage(text, webSearch: _webSearch);
  }

  void _showImageOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  ref
                      .read(chatControllerProvider.notifier)
                      .attachImage(source: ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  ref
                      .read(chatControllerProvider.notifier)
                      .attachImage(source: ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDocumentSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AttachDocumentsSheet(),
    );
  }
}

class _PendingImageBar extends StatelessWidget {
  const _PendingImageBar({
    required this.imagePath,
    required this.ocrLoading,
    required this.ocrText,
    required this.ocrError,
    required this.onRemove,
  });

  final String imagePath;
  final bool ocrLoading;
  final String? ocrText;
  final String? ocrError;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final String status;
    if (ocrLoading) {
      status = 'Reading text from image…';
    } else if (ocrError != null) {
      status = 'No readable text found — you can still send it.';
    } else if (ocrText != null && ocrText!.isNotEmpty) {
      final preview =
          ocrText!.length > 60 ? '${ocrText!.substring(0, 60)}…' : ocrText!;
      status = 'Text found: $preview';
    } else {
      status = 'No readable text found — you can still send it.';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      color: AppColors.cream,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(imagePath),
              width: 52,
              height: 52,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      ocrLoading
                          ? Icons.hourglass_top_rounded
                          : Icons.text_snippet_outlined,
                      size: 15,
                      color: AppColors.sageDeep,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Image attached',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.coffee,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.coffeeSoft,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPromptTap});

  final void Function(String) onPromptTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Row(
            children: [
              const AppLogo(size: 52),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Hi! I\'m your medical study buddy.\nAsk me anything.',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppColors.coffee,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'Try asking:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.coffee.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final prompt in _quickPrompts)
                ActionChip(
                  label: Text(prompt),
                  onPressed: () => onPromptTap(prompt),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isStreaming,
  });

  final ChatMessage message;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppColors.sageDark : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 6),
            bottomRight: Radius.circular(isUser ? 6 : 20),
          ),
          border: isUser
              ? null
              : Border.all(color: AppColors.outlineSoft),
          boxShadow: isUser
              ? null
              : [
                  BoxShadow(
                    color: AppColors.coffee.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: isUser
            ? _UserContent(message: message)
            : _AssistantContent(message: message, isStreaming: isStreaming),
      ),
    );
  }
}

class _UserContent extends StatelessWidget {
  const _UserContent({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (message.imagePath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                File(message.imagePath!),
                width: 180,
                fit: BoxFit.cover,
              ),
            ),
          ),
        if (message.imagePath != null &&
            message.ocrText != null &&
            message.ocrText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.text_snippet_outlined,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 4),
                Text(
                  'Text extracted from image',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        Text(
          message.content,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14.5,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _AssistantContent extends StatelessWidget {
  const _AssistantContent({
    required this.message,
    required this.isStreaming,
  });

  final ChatMessage message;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    if (message.content.isEmpty && isStreaming) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: _TypingDots(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.webSearched && message.sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.public_rounded,
                  size: 14,
                  color: AppColors.mustardDark,
                ),
                const SizedBox(width: 5),
                const Text(
                  'Answered with live web search',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mustardDark,
                  ),
                ),
              ],
            ),
          ),
        MarkdownBody(
          data: message.content,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(
              color: AppColors.coffee,
              fontSize: 14.5,
              height: 1.5,
            ),
            h1: const TextStyle(
              color: AppColors.coffee,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            h2: const TextStyle(
              color: AppColors.coffee,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            h3: const TextStyle(
              color: AppColors.coffee,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            listBullet: const TextStyle(color: AppColors.sageDark),
            strong: const TextStyle(
              color: AppColors.coffee,
              fontWeight: FontWeight.w700,
            ),
            code: TextStyle(
              color: AppColors.acorn,
              backgroundColor: AppColors.sagePale,
              fontSize: 13,
            ),
            tableHead: const TextStyle(
              color: AppColors.coffee,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
            tableBody: const TextStyle(
              color: AppColors.coffee,
              fontSize: 13.5,
            ),
            tableBorder: TableBorder.all(
              color: AppColors.outlineSoft,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        if (isStreaming)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: _TypingDots(),
          ),
        if (!isStreaming && message.sources.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          const Text(
            'Sources',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.coffeeSoft,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < message.sources.length; i++)
                _SourceChip(
                  index: i + 1,
                  source: message.sources[i],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.index, required this.source});

  final int index;
  final WebSource source;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.sagePale,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final uri = Uri.tryParse(source.url);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.sageDark,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$index',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(
                  source.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.coffee,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.open_in_new_rounded,
                size: 12,
                color: AppColors.coffeeSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final t = (_controller.value - delay) % 1.0;
            final scale = 0.6 + 0.4 * (t < 0.5 ? t * 2 : (1 - t) * 2);
            return Container(
              margin: const EdgeInsets.only(right: 4),
              width: 7 * scale,
              height: 7 * scale,
              decoration: const BoxDecoration(
                color: AppColors.sage,
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.isGenerating,
    required this.isSearching,
    required this.modelLoading,
    required this.webSearch,
    required this.onToggleWeb,
    required this.onSend,
    required this.onStop,
    required this.onAttachImage,
    required this.onAttachDocument,
    required this.attachedDocCount,
  });

  final TextEditingController controller;
  final bool isGenerating;
  final bool isSearching;
  final bool modelLoading;
  final bool webSearch;
  final VoidCallback onToggleWeb;
  final void Function(String) onSend;
  final VoidCallback onStop;
  final VoidCallback onAttachImage;
  final VoidCallback onAttachDocument;
  final int attachedDocCount;

  @override
  Widget build(BuildContext context) {
    final busy = isGenerating || isSearching;
    final canSend =
        controller.text.trim().isNotEmpty && !busy && !modelLoading;

    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        8,
        14,
        MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.cream,
        border: Border(
          top: BorderSide(color: AppColors.outlineSoft.withValues(alpha: 0.8)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _ToolChip(
                icon: Icons.attach_file_rounded,
                label: 'Docs',
                onTap: onAttachDocument,
                badgeCount: attachedDocCount > 0 ? attachedDocCount : null,
              ),
              const SizedBox(width: 8),
              _ToolChip(
                icon: Icons.image_outlined,
                label: 'Image',
                onTap: onAttachImage,
              ),
              const SizedBox(width: 8),
              _ToolChip(
                icon: Icons.public_rounded,
                label: 'Web',
                active: webSearch,
                onTap: onToggleWeb,
              ),
              if (webSearch) ...[
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Will search the web for the latest info',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.mustardDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 130),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.outlineSoft),
                  ),
                  child: TextField(
                    controller: controller,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (text) {
                      if (canSend) onSend(text);
                    },
                    decoration: const InputDecoration(
                      hintText: 'Ask me anything medical…',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      hintStyle: TextStyle(
                        color: AppColors.coffeeSoft,
                        fontSize: 14.5,
                      ),
                    ),
                    style: const TextStyle(
                      color: AppColors.coffee,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                child: Material(
                  color: isGenerating
                      ? AppColors.mustard
                      : (canSend ? AppColors.sageDark : AppColors.sageLight),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: isGenerating
                        ? onStop
                        : (canSend ? () => onSend(controller.text) : null),
                    child: Icon(
                      isGenerating
                          ? Icons.stop_rounded
                          : Icons.arrow_upward_rounded,
                      color: isGenerating
                          ? AppColors.coffee
                          : (canSend ? Colors.white : AppColors.coffeeSoft),
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.badgeCount,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.mustardPale : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: badgeCount != null ? 6 : 12,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? AppColors.mustard : AppColors.outlineSoft,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badgeCount != null && badgeCount! > 0) ...[
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  constraints: BoxConstraints(minWidth: badgeCount!.toString().length * 7 + 12),
                  decoration: BoxDecoration(
                    color: AppColors.sageDeep,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
              Icon(
                icon,
                size: 16,
                color: active ? AppColors.mustardDark : AppColors.sageDeep,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.mustardDark : AppColors.coffeeSoft,
                ),
              ),
              if (badgeCount != null && badgeCount! > 0) const SizedBox(width: 5),
            ],
          ),
        ),
      ),
    );
  }
}
