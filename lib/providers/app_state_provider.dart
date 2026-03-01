import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_state.dart';

/// Bubble state for floating overlay
enum BubbleState { idle, listening, working, paused, answer }

/// Event types from bubble taps
enum BubbleEvent { startListening, stopListening, stop, pause, resume, ask }

class AppStateProvider extends ChangeNotifier {
  AppScreen _currentScreen = AppScreen.onboarding;
  RingState _ringState = RingState.idle;
  String _transcript = '';
  TaskResult? _lastResult;
  final List<HistoryItem> _history = [];
  bool _onboardingComplete = false;

  // Agent mode params
  String _agentAppPackage = '';
  String _agentGoal = '';
  String _agentLanguage = '';

  // Bubble state
  BubbleState _bubbleState = BubbleState.idle;
  BubbleEvent? _lastBubbleEvent;
  final List<VoidCallback> _bubbleEventListeners = [];

  // Bubble MethodChannel
  static const _bubbleChannel = MethodChannel('bharat_voice_os/bubble');

  // Getters
  AppScreen get currentScreen => _currentScreen;
  RingState get ringState => _ringState;
  String get transcript => _transcript;
  TaskResult? get lastResult => _lastResult;
  List<HistoryItem> get history => _history;
  bool get onboardingComplete => _onboardingComplete;
  String get agentAppPackage => _agentAppPackage;
  String get agentGoal => _agentGoal;
  String get agentLanguage => _agentLanguage;
  BubbleState get bubbleState => _bubbleState;
  BubbleEvent? get lastBubbleEvent => _lastBubbleEvent;

  /// Add a listener for bubble events
  void addBubbleEventListener(VoidCallback listener) {
    _bubbleEventListeners.add(listener);
  }

  /// Remove a listener for bubble events
  void removeBubbleEventListener(VoidCallback listener) {
    _bubbleEventListeners.remove(listener);
  }

  /// Notify all bubble event listeners
  void _notifyBubbleEventListeners() {
    for (final listener in _bubbleEventListeners) {
      listener();
    }
  }

  /// Handle bubble event from native
  void handleBubbleEvent(BubbleEvent event) {
    _lastBubbleEvent = event;
    _notifyBubbleEventListeners();
    notifyListeners();
  }

  /// Update bubble state and sync with native
  Future<void> updateBubbleState(BubbleState state) async {
    _bubbleState = state;
    notifyListeners();

    // Sync with native FloatingBubbleService
    try {
      await _bubbleChannel.invokeMethod('updateBubbleState', {
        'state': state.name,
      });
    } catch (e) {
      debugPrint('Failed to update bubble state: $e');
    }
  }

  /// Show the floating bubble
  Future<void> showBubble() async {
    try {
      await _bubbleChannel.invokeMethod('showBubble');
      _bubbleState = BubbleState.idle;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to show bubble: $e');
    }
  }

  /// Hide the floating bubble
  Future<void> hideBubble() async {
    try {
      await _bubbleChannel.invokeMethod('hideBubble');
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to hide bubble: $e');
    }
  }

  void setOnboardingComplete(bool value) {
    _onboardingComplete = value;
    if (value) {
      _currentScreen = AppScreen.home;
    }
    notifyListeners();
  }

  void navigateTo(AppScreen screen) {
    _currentScreen = screen;
    notifyListeners();
  }

  void setRingState(RingState state) {
    _ringState = state;
    notifyListeners();
  }

  void updateTranscript(String text) {
    _transcript = text;
    notifyListeners();
  }

  void clearTranscript() {
    _transcript = '';
    notifyListeners();
  }

  void setResult(TaskResult result) {
    _lastResult = result;
    // Add to history
    _history.insert(
      0,
      HistoryItem(
        icon: _iconForMode(result.mode),
        title: result.title,
        subtitle:
            result.answer ??
            result.details?.map((d) => d.text).join(' · ') ??
            '',
        time: _formatTime(DateTime.now()),
      ),
    );
    // Navigate to appropriate result screen
    switch (result.mode) {
      case 'agent':
        _currentScreen = AppScreen.resultAgent;
        break;
      case 'answer':
        _currentScreen = AppScreen.resultAnswer;
        break;
      case 'confirm':
        _currentScreen = AppScreen.confirmation;
        break;
    }
    notifyListeners();
  }

  void startListening() {
    _ringState = RingState.listening;
    _transcript = '';
    _currentScreen = AppScreen.listening;
    notifyListeners();
  }

  void startProcessing() {
    _ringState = RingState.processing;
    _currentScreen = AppScreen.processing;
    notifyListeners();
  }

  void startAgentMode({
    required String appPackage,
    required String goal,
    required String language,
  }) {
    _agentAppPackage = appPackage;
    _agentGoal = goal;
    _agentLanguage = language;
    _currentScreen = AppScreen.agentMode;
    notifyListeners();
  }

  void goHome() {
    _ringState = RingState.idle;
    _currentScreen = AppScreen.home;
    _transcript = '';
    notifyListeners();
  }

  String _iconForMode(String mode) {
    switch (mode) {
      case 'agent':
        return '🚕';
      case 'answer':
        return '📋';
      case 'confirm':
        return '💬';
      default:
        return '✨';
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $ampm';
  }
}
