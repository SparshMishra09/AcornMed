import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'data/services/document_service.dart';
import 'data/services/knowledge_service.dart';
import 'data/services/storage_service.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await StorageService.instance.init();
  unawaited(_initKnowledge());
  runApp(const ProviderScope(child: AcornMedApp()));
}

Future<void> _initKnowledge() async {
  await KnowledgeService.instance.init();
  await DocumentService.instance.reindexAll();
}

void unawaited(Future<void> future) {}

class AcornMedApp extends StatelessWidget {
  const AcornMedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AcornMed',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const RootGate(),
    );
  }
}

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _checkedOnboarding = false;
  bool _onboarded = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _onboarded = prefs.getBool('onboarded') ?? false;
      _checkedOnboarding = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SplashScreen(
      onFinished: () {
        if (!_checkedOnboarding) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => _onboarded
                ? const HomeScreen()
                : const OnboardingScreen(),
          ),
        );
      },
      ready: _checkedOnboarding,
    );
  }
}
