import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/app_state_provider.dart';
import 'models/app_state.dart';
import 'screens/voice_chat_screen.dart';
import 'screens/result_agent_screen.dart';
import 'screens/result_answer_screen.dart';
import 'screens/confirmation_screen.dart';
import 'screens/history_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/agent_mode_screen.dart';
import 'services/history_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for history storage
  await HistoryService.init();

  final prefs = await SharedPreferences.getInstance();
  final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;

  runApp(BharatVoiceApp(onboardingComplete: onboardingComplete));
}

class BharatVoiceApp extends StatelessWidget {
  final bool onboardingComplete;

  const BharatVoiceApp({super.key, required this.onboardingComplete});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        final provider = AppStateProvider();
        if (onboardingComplete) {
          provider.setOnboardingComplete(true);
        }
        return provider;
      },
      child: MaterialApp(
        title: 'Bharat Voice OS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          fontFamily: GoogleFonts.inter().fontFamily,
        ),
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.center,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: _buildScreen(context, appState.currentScreen, appState),
    );
  }

  Widget _buildScreen(BuildContext context, AppScreen screen, AppStateProvider appState) {
    switch (screen) {
      case AppScreen.onboarding:
        return const OnboardingScreen(key: ValueKey('onboarding'));
      case AppScreen.home:
      case AppScreen.listening:
      case AppScreen.processing:
        // All handled by the unified VoiceChatScreen
        return const VoiceChatScreen(key: ValueKey('voiceChat'));
      case AppScreen.resultAgent:
        return const ResultAgentScreen(key: ValueKey('resultAgent'));
      case AppScreen.resultAnswer:
        return const ResultAnswerScreen(key: ValueKey('resultAnswer'));
      case AppScreen.confirmation:
        return const ConfirmationScreen(key: ValueKey('confirmation'));
      case AppScreen.history:
        return const HistoryScreen(key: ValueKey('history'));
      case AppScreen.agentMode:
        return AgentModeScreen(
          key: const ValueKey('agentMode'),
          appPackage: appState.agentAppPackage,
          goal: appState.agentGoal,
          detectedLanguage: appState.agentLanguage,
        );
    }
  }
}
