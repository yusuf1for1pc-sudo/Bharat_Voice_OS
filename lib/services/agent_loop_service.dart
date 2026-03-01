import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'hardcoded_flow_service.dart';

/// Represents one step update in the agent loop.
class AgentStepUpdate {
  final int stepNumber;
  final String actionTaken;
  final String reason;
  final String narrationText;
  final bool isComplete;
  final bool isFailed;
  final bool needsConfirm;
  final String? confirmMessage;
  final List<Map<String, dynamic>>? confirmDetails;
  final String? result;
  final List<Map<String, dynamic>>? resultDetails;

  AgentStepUpdate({
    required this.stepNumber,
    required this.actionTaken,
    required this.reason,
    this.narrationText = '',
    this.isComplete = false,
    this.isFailed = false,
    this.needsConfirm = false,
    this.confirmMessage,
    this.confirmDetails,
    this.result,
    this.resultDetails,
  });
}

/// AgentLoopService — manages the vision agent loop.
/// Opens app → captures screenshot → calls /agent_step → executes gesture → repeat.
class AgentLoopService {
  static const _accessibilityChannel = MethodChannel(
    'bharat_voice_os/accessibility',
  );
  static const _screenshotChannel = MethodChannel('bharat_voice_os/screenshot');
  static const _bubbleChannel = MethodChannel('bharat_voice_os/bubble');
  static const _bubbleEventsChannel = MethodChannel(
    'bharat_voice_os/bubble_events',
  );

  StreamController<AgentStepUpdate> _controller =
      StreamController<AgentStepUpdate>.broadcast();
  Stream<AgentStepUpdate> get updates => _controller.stream;

  // Interrupt stream — emits when user uses pill controls
  StreamController<String> _interruptController =
      StreamController<String>.broadcast();
  Stream<String> get interrupts => _interruptController.stream;

  bool _isRunning = false;
  bool _isPaused = false;
  bool _isInterrupted = false; // For ask/question mode
  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  bool get isInterrupted => _isInterrupted;

  final List<Map<String, dynamic>> _history = [];

  /// Ensure stream controllers are open
  void _ensureControllersOpen() {
    if (_controller.isClosed) {
      _controller = StreamController<AgentStepUpdate>.broadcast();
    }
    if (_interruptController.isClosed) {
      _interruptController = StreamController<String>.broadcast();
    }
  }

  /// Set up handlers for pill control buttons (stop, pause, resume, ask)
  void setupBubbleTapHandler() {
    _bubbleEventsChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onBubbleTap':
          // Legacy tap behavior — treat as ask
          _handleAsk();
          break;
        case 'onBubbleStop':
          _handleStop();
          break;
        case 'onBubblePause':
          _handlePause();
          break;
        case 'onBubbleResume':
          _handleResume();
          break;
        case 'onBubbleAsk':
          _handleAsk();
          break;
      }
    });
  }

  /// Handle Stop button — completely stop the agent task
  void _handleStop() {
    if (!_isRunning) return;

    _interruptController.add('stopped');
    _controller.add(
      AgentStepUpdate(
        stepNumber: -1,
        actionTaken: 'stopped',
        reason: 'User stopped the task',
        narrationText: 'Task stopped',
        isFailed: true,
      ),
    );

    stopLoop();
  }

  /// Handle Pause button — pause without interrupting
  void _handlePause() {
    if (!_isRunning || _isPaused) return;

    _isPaused = true;
    _interruptController.add('paused');
    _controller.add(
      AgentStepUpdate(
        stepNumber: -1,
        actionTaken: 'paused',
        reason: 'User paused the task',
        narrationText: 'Paused',
      ),
    );
  }

  /// Handle Resume button — resume from pause
  void _handleResume() {
    if (!_isRunning || !_isPaused || _isInterrupted) return;

    _isPaused = false;
    try {
      _bubbleChannel.invokeMethod('updateBubbleState', {'state': 'resuming'});
    } catch (_) {}
    _interruptController.add('resumed');
    _controller.add(
      AgentStepUpdate(
        stepNumber: -1,
        actionTaken: 'resumed',
        reason: 'User resumed the task',
        narrationText: 'Resuming...',
      ),
    );
  }

  /// Handle Ask button — interrupt to ask a question without abandoning task
  void _handleAsk() {
    if (!_isRunning) return;

    if (_isInterrupted) {
      // Already in ask mode — user tapped again to resume
      resumeAfterInterrupt();
    } else {
      // Pause the agent and go into listening mode for question
      _isInterrupted = true;
      _isPaused = true;
      try {
        _bubbleChannel.invokeMethod('updateBubbleState', {
          'state': 'listening',
        });
      } catch (_) {}
      _interruptController.add('interrupted');
      _controller.add(
        AgentStepUpdate(
          stepNumber: -1,
          actionTaken: 'interrupted',
          reason: 'User wants to ask a question',
          narrationText: 'Listening...',
        ),
      );
    }
  }

  /// Resume after user interrupt (voice question answered).
  void resumeAfterInterrupt() {
    _isInterrupted = false;
    _isPaused = false;
    try {
      _bubbleChannel.invokeMethod('updateBubbleState', {'state': 'resuming'});
    } catch (_) {}
    _interruptController.add('resumed');
    _controller.add(
      AgentStepUpdate(
        stepNumber: -1,
        actionTaken: 'resumed',
        reason: 'Resuming task',
        narrationText: 'Resuming...',
      ),
    );
  }

  /// Pause for interrupt (called from UI pause button).
  void pauseForInterrupt() {
    if (!_isRunning || _isInterrupted) return;
    _handlePause();
  }

  /// Run hardcoded WhatsApp messaging flow (bypasses AI vision for reliability)
  Future<void> _runHardcodedWhatsAppFlow({
    required String contactName,
    required String message,
    required String detectedLanguage,
  }) async {
    debugPrint('AgentLoop: Running hardcoded WhatsApp flow for $contactName');

    // Step 0: Opening app narration
    _controller.add(
      AgentStepUpdate(
        stepNumber: 0,
        actionTaken: 'opening_app',
        reason: 'Opening WhatsApp',
        narrationText: detectedLanguage.startsWith('hi')
            ? 'WhatsApp खोल रहा हूं...'
            : 'Opening WhatsApp...',
      ),
    );

    // Open WhatsApp
    try {
      await _accessibilityChannel.invokeMethod('openApp', {
        'package': 'com.whatsapp',
      });
    } catch (e) {
      debugPrint('AgentLoop: Failed to open WhatsApp: $e');
    }

    // Wait for WhatsApp to load
    await Future.delayed(const Duration(milliseconds: 2000));

    // Move our app to background so gestures work on WhatsApp
    try {
      await _accessibilityChannel.invokeMethod('moveToBackground');
    } catch (e) {
      debugPrint('AgentLoop: moveToBackground failed: $e');
    }

    await Future.delayed(const Duration(milliseconds: 500));

    // Run the hardcoded flow with step updates
    final success = await HardcodedFlowService.sendWhatsAppMessage(
      contactName: contactName,
      message: message,
      onStep: (step, description) {
        if (!_isRunning) return;

        String narration;
        if (detectedLanguage.startsWith('hi')) {
          switch (step) {
            case 1:
              narration = 'खोज रहा हूं...';
              break;
            case 2:
              narration = '$contactName टाइप कर रहा हूं...';
              break;
            case 3:
              narration = '$contactName चुन रहा हूं...';
              break;
            case 4:
              narration = 'मैसेज बॉक्स पर जा रहा हूं...';
              break;
            case 5:
              narration = 'मैसेज लिख रहा हूं...';
              break;
            case 6:
              narration = 'भेज रहा हूं...';
              break;
            default:
              narration = description;
          }
        } else {
          narration = description;
        }

        _controller.add(
          AgentStepUpdate(
            stepNumber: step,
            actionTaken: 'hardcoded_step',
            reason: description,
            narrationText: narration,
          ),
        );
      },
    );

    // Final result
    if (success) {
      _controller.add(
        AgentStepUpdate(
          stepNumber: 7,
          actionTaken: 'done',
          reason: 'Message sent successfully',
          narrationText: detectedLanguage.startsWith('hi')
              ? '$contactName को मैसेज भेज दिया!'
              : 'Message sent to $contactName!',
          isComplete: true,
          result: detectedLanguage.startsWith('hi')
              ? '$contactName को "$message" भेज दिया'
              : 'Sent "$message" to $contactName',
        ),
      );
    } else {
      _controller.add(
        AgentStepUpdate(
          stepNumber: 7,
          actionTaken: 'failed',
          reason: 'Failed to send message',
          narrationText: detectedLanguage.startsWith('hi')
              ? 'मैसेज भेजने में समस्या हुई'
              : 'Failed to send message',
          isFailed: true,
        ),
      );
    }

    _isRunning = false;

    // Show bubble again after task completion
    try {
      await _bubbleChannel.invokeMethod('showBubble', {'state': 'idle'});
    } catch (_) {}

    // Release wake lock but DON'T bring app to front - let user stay in the target app
    try {
      await _accessibilityChannel.invokeMethod('releaseWakeLock');
    } catch (_) {}
  }

  /// Run hardcoded Rapido cab booking flow (bypasses AI vision for reliability)
  Future<void> _runHardcodedRapidoFlow({
    required String destination,
    required String detectedLanguage,
  }) async {
    debugPrint('AgentLoop: Running hardcoded Rapido flow for $destination');

    // Step 0: Opening app narration
    _controller.add(
      AgentStepUpdate(
        stepNumber: 0,
        actionTaken: 'opening_app',
        reason: 'Opening Rapido',
        narrationText: detectedLanguage.startsWith('hi')
            ? 'Rapido खोल रहा हूं...'
            : 'Opening Rapido...',
      ),
    );

    // Open Rapido
    try {
      await _accessibilityChannel.invokeMethod('openApp', {
        'package': 'com.rapido.passenger',
      });
    } catch (e) {
      debugPrint('AgentLoop: Failed to open Rapido: $e');
    }

    // Wait for Rapido to load
    await Future.delayed(const Duration(milliseconds: 2500));

    // Move our app to background so gestures work on Rapido
    try {
      await _accessibilityChannel.invokeMethod('moveToBackground');
    } catch (e) {
      debugPrint('AgentLoop: moveToBackground failed: $e');
    }

    await Future.delayed(const Duration(milliseconds: 500));

    // Run the hardcoded flow with step updates
    final success = await HardcodedFlowService.bookRapidoCab(
      destination: destination,
      onStep: (step, description) {
        if (!_isRunning) return;

        String narration;
        if (detectedLanguage.startsWith('hi')) {
          switch (step) {
            case 1:
              narration = 'गंतव्य फील्ड टैप कर रहा हूं...';
              break;
            case 2:
              narration = 'ड्रॉप लोकेशन चुन रहा हूं...';
              break;
            case 3:
              narration = '$destination टाइप कर रहा हूं...';
              break;
            case 4:
              narration = '$destination चुन रहा हूं...';
              break;
            case 5:
              narration = 'राइड ऑप्शन दिखा रहा हूं...';
              break;
            case 6:
              narration = 'प्रीमियम चुन रहा हूं...';
              break;
            case 7:
              narration = 'कैब बुक कर रहा हूं...';
              break;
            case 8:
              narration = 'पिकअप कन्फर्म कर रहा हूं...';
              break;
            case 9:
              narration = 'बुकिंग कन्फर्म कर रहा हूं...';
              break;
            default:
              narration = description;
          }
        } else {
          narration = description;
        }

        _controller.add(
          AgentStepUpdate(
            stepNumber: step,
            actionTaken: 'hardcoded_step',
            reason: description,
            narrationText: narration,
          ),
        );
      },
    );

    // Final result
    if (success) {
      _controller.add(
        AgentStepUpdate(
          stepNumber: 9,
          actionTaken: 'done',
          reason: 'Cab booked successfully',
          narrationText: detectedLanguage.startsWith('hi')
              ? '$destination के लिए कैब बुक हो गई!'
              : 'Cab booked to $destination!',
          isComplete: true,
          result: detectedLanguage.startsWith('hi')
              ? '$destination के लिए Rapido कैब बुक हो गई'
              : 'Rapido cab booked to $destination',
        ),
      );
    } else {
      _controller.add(
        AgentStepUpdate(
          stepNumber: 9,
          actionTaken: 'failed',
          reason: 'Failed to book cab',
          narrationText: detectedLanguage.startsWith('hi')
              ? 'कैब बुक करने में समस्या हुई'
              : 'Failed to book cab',
          isFailed: true,
        ),
      );
    }

    _isRunning = false;

    // Show bubble again after task completion
    try {
      await _bubbleChannel.invokeMethod('showBubble', {'state': 'idle'});
    } catch (_) {}

    // Release wake lock but DON'T bring app to front - let user stay in Rapido
    try {
      await _accessibilityChannel.invokeMethod('releaseWakeLock');
    } catch (_) {}
  }

  /// Start the vision agent loop.
  Future<void> startLoop({
    required String appPackage,
    required String goal,
    required String detectedLanguage,
  }) async {
    _ensureControllersOpen();
    _isRunning = true;
    _isPaused = false;
    _history.clear();

    // Acquire wake lock to prevent background killing
    try {
      await _accessibilityChannel.invokeMethod('acquireWakeLock');
      debugPrint('AgentLoop: WakeLock acquired');
    } catch (e) {
      debugPrint('AgentLoop: WakeLock failed: $e');
    }

    // Show floating pill (working mode) over all apps
    try {
      await _bubbleChannel.invokeMethod('showPill');
    } catch (e) {
      debugPrint('AgentLoopService: failed to show floating pill: $e');
    }

    // ════════════════════════════════════════════════════════════════
    // CHECK FOR HARDCODED FLOWS FIRST (faster, more reliable for demo)
    // ════════════════════════════════════════════════════════════════

    // Check if this is a WhatsApp message request
    final whatsappData = HardcodedFlowService.parseWhatsAppGoal(goal);
    if (whatsappData != null && appPackage == 'com.whatsapp') {
      debugPrint('AgentLoop: Using HARDCODED WhatsApp flow');
      await _runHardcodedWhatsAppFlow(
        contactName: whatsappData['contact']!,
        message: whatsappData['message']!,
        detectedLanguage: detectedLanguage,
      );
      return;
    }

    // Check if this is a Rapido booking request (by app package, not goal text)
    if (appPackage == 'com.rapido.passenger') {
      // Extract destination from goal - remove common prefixes
      String destination = goal
          .replaceAll(
            RegExp(
              r'^(book(ed)?|get|order|call)\s+(a\s+)?cab\s+(for|to)\s+',
              caseSensitive: false,
            ),
            '',
          )
          .replaceAll(
            RegExp(r'^(rapido\s+)?(to\s+)?', caseSensitive: false),
            '',
          )
          .replaceAll(RegExp(r'[.,!?]+$'), '')
          .trim();

      // If destination is empty or too generic, use a default
      if (destination.isEmpty || destination.length < 3) {
        destination = 'Phoenix Mall';
      }

      debugPrint(
        'AgentLoop: Using HARDCODED Rapido flow - Destination: $destination',
      );
      await _runHardcodedRapidoFlow(
        destination: destination,
        detectedLanguage: detectedLanguage,
      );
      return;
    }

    // ════════════════════════════════════════════════════════════════
    // FALLBACK TO AI VISION LOOP
    // ════════════════════════════════════════════════════════════════

    // Step 1: Emit opening narration
    _controller.add(
      AgentStepUpdate(
        stepNumber: 0,
        actionTaken: 'opening_app',
        reason: 'Opening the app',
        narrationText: detectedLanguage.startsWith('hi')
            ? 'App khol raha hun'
            : 'Opening the app',
      ),
    );

    // Step 2: Open the app via Kotlin
    bool appOpened = false;
    if (appPackage.isNotEmpty) {
      try {
        debugPrint('AgentLoop: Opening app $appPackage');
        final result = await _accessibilityChannel.invokeMethod<bool>(
          'openApp',
          {'package': appPackage},
        );
        appOpened = result ?? false;
        debugPrint('AgentLoop: openApp result=$appOpened');
      } catch (e) {
        debugPrint('AgentLoop: Failed to open app: $e');
      }
    }

    // Wait for the target app to fully launch
    await Future.delayed(Duration(milliseconds: appOpened ? 1500 : 500));

    // Move our app to the background so screenshots capture the target app
    try {
      debugPrint('AgentLoop: Moving to background');
      await _accessibilityChannel.invokeMethod('moveToBackground');
      debugPrint('AgentLoop: moveToBackground succeeded');
    } catch (e) {
      debugPrint('AgentLoop: moveToBackground failed: $e');
    }

    // Wait for UI to settle
    await Future.delayed(const Duration(milliseconds: 2000));

    // Step 3: Begin vision loop (max 15 iterations)
    for (int step = 1; step <= 15; step++) {
      if (!_isRunning) break;

      // Wait if paused (confirm_needed)
      while (_isPaused && _isRunning) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      if (!_isRunning) break;

      // 3a: Capture screenshot (with retry logic for background recovery)
      String? screenshotB64;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          screenshotB64 = await _screenshotChannel.invokeMethod<String>(
            'captureScreen',
          );
          if (screenshotB64 != null && screenshotB64.isNotEmpty) break;
        } catch (e) {
          debugPrint('AgentLoop: Screenshot attempt ${attempt + 1} failed: $e');
          if (attempt < 2) {
            await Future.delayed(const Duration(milliseconds: 1000));
          }
        }
      }

      if (!_isRunning) break;

      if (screenshotB64 == null || screenshotB64.isEmpty) {
        _controller.add(
          AgentStepUpdate(
            stepNumber: step,
            actionTaken: 'failed',
            reason: 'Could not capture screen after 3 attempts',
            isFailed: true,
          ),
        );
        break;
      }

      // 3b: Call backend /agent_step
      final actionData = await ApiService.agentStep(
        screenshotBase64: screenshotB64,
        goal: goal,
        history: _history,
        stepNumber: step,
      );

      final action = actionData['action'] as String? ?? 'failed';
      final reason = actionData['reason'] as String? ?? '';

      // Add to history
      _history.add({'action': action, 'reason': reason, ...actionData});

      // 3c: Handle action
      switch (action) {
        case 'tap':
          final x = actionData['x'] as int? ?? 0;
          final y = actionData['y'] as int? ?? 0;
          await _executeGesture({'action': 'tap', 'x': x, 'y': y});
          _controller.add(
            AgentStepUpdate(
              stepNumber: step,
              actionTaken: 'tap',
              reason: reason,
              narrationText: 'Tap at ($x, $y)',
            ),
          );
          break;

        case 'type':
          final text = actionData['text'] as String? ?? '';
          await _executeGesture({'action': 'type', 'text': text});
          _controller.add(
            AgentStepUpdate(
              stepNumber: step,
              actionTaken: 'type',
              reason: reason,
              narrationText: 'Typing: $text',
            ),
          );
          break;

        case 'scroll':
          final direction = actionData['direction'] as String? ?? 'down';
          final distance = actionData['distance'] as int? ?? 500;
          await _executeGesture({
            'action': 'scroll',
            'direction': direction,
            'distance': distance,
          });
          _controller.add(
            AgentStepUpdate(
              stepNumber: step,
              actionTaken: 'scroll',
              reason: reason,
              narrationText: 'Scrolling $direction',
            ),
          );
          break;

        case 'swipe':
          await _executeGesture({
            'action': 'swipe',
            'x1': actionData['x1'],
            'y1': actionData['y1'],
            'x2': actionData['x2'],
            'y2': actionData['y2'],
          });
          _controller.add(
            AgentStepUpdate(
              stepNumber: step,
              actionTaken: 'swipe',
              reason: reason,
              narrationText: 'Swiping',
            ),
          );
          break;

        case 'back':
          await _executeGesture({'action': 'back'});
          _controller.add(
            AgentStepUpdate(
              stepNumber: step,
              actionTaken: 'back',
              reason: reason,
              narrationText: 'Going back',
            ),
          );
          break;

        case 'wait':
          final seconds = actionData['seconds'] as int? ?? 2;
          await Future.delayed(Duration(seconds: seconds));
          _controller.add(
            AgentStepUpdate(
              stepNumber: step,
              actionTaken: 'wait',
              reason: reason,
              narrationText: 'Waiting...',
            ),
          );
          break;

        case 'confirm_needed':
          final message = actionData['message'] as String? ?? 'Confirm?';
          final details = (actionData['details'] as List<dynamic>?)
              ?.map((d) => Map<String, dynamic>.from(d as Map))
              .toList();
          _isPaused = true;
          try {
            // Keep in paused state (still shows pill)
            _bubbleChannel.invokeMethod('updateBubbleState', {
              'state': 'paused',
            });
          } catch (_) {}
          _controller.add(
            AgentStepUpdate(
              stepNumber: step,
              actionTaken: 'confirm_needed',
              reason: reason,
              narrationText: message,
              needsConfirm: true,
              confirmMessage: message,
              confirmDetails: details,
            ),
          );
          break;

        case 'done':
          final resultText =
              actionData['result'] as String? ?? 'Task completed';
          final details = (actionData['details'] as List<dynamic>?)
              ?.map((d) => Map<String, dynamic>.from(d as Map))
              .toList();
          _controller.add(
            AgentStepUpdate(
              stepNumber: step,
              actionTaken: 'done',
              reason: reason,
              narrationText: resultText,
              isComplete: true,
              result: resultText,
              resultDetails: details,
            ),
          );
          _isRunning = false;
          break;

        case 'failed':
        default:
          _controller.add(
            AgentStepUpdate(
              stepNumber: step,
              actionTaken: 'failed',
              reason: reason,
              narrationText: reason,
              isFailed: true,
            ),
          );
          _isRunning = false;
          break;
      }

      // Stuck detection: same coordinates 3 times in a row
      if (_history.length >= 3) {
        final last3 = _history.sublist(_history.length - 3);
        final allSameCoords = last3.every(
          (h) =>
              h['action'] == 'tap' &&
              h['x'] == last3[0]['x'] &&
              h['y'] == last3[0]['y'],
        );
        if (allSameCoords) {
          _controller.add(
            AgentStepUpdate(
              stepNumber: step,
              actionTaken: 'failed',
              reason: 'Stuck: same action repeated 3 times',
              isFailed: true,
            ),
          );
          _isRunning = false;
          break;
        }
      }

      // Wait for screen to update before next screenshot
      if (_isRunning && action != 'wait') {
        await Future.delayed(const Duration(milliseconds: 1500));
      }
    }

    _isRunning = false;
    try {
      _bubbleChannel.invokeMethod('hideBubble');
    } catch (_) {}
  }

  Future<void> _executeGesture(Map<String, dynamic> params) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        await _accessibilityChannel.invokeMethod('executeGesture', {
          'params': params,
        });
        return; // success
      } catch (e) {
        debugPrint('AgentLoop: Gesture attempt ${attempt + 1} failed: $e');
        if (attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
    }
    debugPrint('AgentLoop: Gesture failed after 3 retries');
  }

  /// Resume the loop after user confirms.
  void resumeAfterConfirm() {
    _isPaused = false;
    try {
      _bubbleChannel.invokeMethod('updateBubbleState', {'state': 'working'});
    } catch (_) {}
  }

  /// Stop the loop immediately.
  void stopLoop() {
    _isRunning = false;
    _isPaused = false;
    _isInterrupted = false;
    try {
      _bubbleChannel.invokeMethod('hideBubble');
    } catch (_) {}
    // Release wake lock
    try {
      _accessibilityChannel.invokeMethod('releaseWakeLock');
    } catch (_) {}
    // Bring our app back to foreground
    try {
      _accessibilityChannel.invokeMethod('bringToFront');
    } catch (_) {}
  }

  void dispose() {
    _isRunning = false;
    _controller.close();
    _interruptController.close();
    _bubbleEventsChannel.setMethodCallHandler(null);
    try {
      _accessibilityChannel.invokeMethod('releaseWakeLock');
    } catch (_) {}
  }
}
