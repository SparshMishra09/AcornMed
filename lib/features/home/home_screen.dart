import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo.dart';
import '../../data/services/ai_engine.dart';
import '../../providers/chat_providers.dart';
import '../model_setup/model_setup_screen.dart';
import 'chat_view.dart';
import 'history_drawer.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(chatControllerProvider.notifier).init());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    final engineStatus = ref.watch(engineStatusProvider).value ?? EngineStatus.idle;

    final needsModel = state.modelFile == null;

    return Scaffold(
      drawer: const HistoryDrawer(),
      appBar: AppBar(
        title: Row(
          children: [
            const AppLogo(size: 34),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'AcornMed',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          _StatusPill(status: engineStatus, loading: state.modelLoading),
          const SizedBox(width: 8),
        ],
      ),
      body: needsModel
          ? const _NoModelView()
          : ChatView(state: state),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.loading});

  final EngineStatus status;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch ((loading, status)) {
      (true, _) => ('Loading…', AppColors.mustardDark),
      (_, EngineStatus.ready) => ('Ready', AppColors.sageDark),
      (_, EngineStatus.generating) => ('Thinking…', AppColors.mustardDark),
      (_, EngineStatus.loading) => ('Loading…', AppColors.mustardDark),
      (_, EngineStatus.error) => ('Error', AppColors.error),
      _ => ('Idle', AppColors.coffeeSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoModelView extends StatelessWidget {
  const _NoModelView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: AppColors.mustard.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.smart_toy_outlined,
                size: 54,
                color: AppColors.mustardDark,
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Set up your AI brain',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.coffee,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Download the AI model once (or import your own GGUF file). '
              'After that, everything works fully offline and private.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.coffee.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ModelSetupScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text('Set up model'),
            ),
          ],
        ),
      ),
    );
  }
}
