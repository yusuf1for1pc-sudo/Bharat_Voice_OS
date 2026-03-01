import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../providers/app_state_provider.dart';
import '../services/agent_loop_service.dart';
import '../services/audio_service.dart';
import '../services/api_service.dart';
import '../widgets/animated_dotted_ring.dart';

/// AgentModeScreen — shows the dotted ring in processing state,
/// streams narration lines from AgentLoopService,
/// shows current step count, and has a stop button.
/// Supports bubble-tap interrupts for user questions mid-task.
class AgentModeScreen extends StatefulWidget {
  final String appPackage;
  final String goal;
  final String detectedLanguage;

  const AgentModeScreen({
    super.key,
    required this.appPackage,
    required this.goal,
    required this.detectedLanguage,
  });

  @override
  State<AgentModeScreen> createState() => _AgentModeScreenState();
}

class _AgentModeScreenState extends State<AgentModeScreen>
    with WidgetsBindingObserver {
  final AgentLoopService _agentLoop = AgentLoopService();
  final AudioService _audioService = AudioService();
  final List<String> _narrationLines = [];
  int _currentStep = 0;
  bool _isDone = false;
  bool _isFailed = false;
  bool _isInterrupted = false;
  bool _isRecording = false;
  String _resultText = '';
  String _interruptTranscript = '';
  String _interruptAnswer = '';
  StreamSubscription<AgentStepUpdate>? _subscription;
  StreamSubscription<String>? _interruptSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAgent();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('AgentModeScreen lifecycle: $state');
  }

  void _startAgent() {
    // Set up bubble tap handler FIRST
    _agentLoop.setupBubbleTapHandler();

    // Update bubble to working/pill mode
    final appState = context.read<AppStateProvider>();
    appState.updateBubbleState(BubbleState.working);

    // Listen for interrupts from pill controls
    _interruptSubscription = _agentLoop.interrupts.listen((event) {
      if (!mounted) return;
      switch (event) {
        case 'interrupted':
          setState(() {
            _isInterrupted = true;
            _interruptTranscript = '';
            _interruptAnswer = '';
          });
          break;
        case 'resumed':
          setState(() {
            _isInterrupted = false;
            _isRecording = false;
          });
          // Update bubble back to working
          appState.updateBubbleState(BubbleState.working);
          break;
        case 'paused':
          setState(() {
            _narrationLines.insert(0, 'Paused');
            if (_narrationLines.length > 5) _narrationLines.removeLast();
          });
          // Update bubble to paused
          appState.updateBubbleState(BubbleState.paused);
          break;
        case 'stopped':
          // User stopped the task from pill control - hide bubble and go home
          appState.updateBubbleState(BubbleState.idle);
          if (mounted) {
            appState.goHome();
          }
          break;
      }
    });

    _subscription = _agentLoop.updates.listen((update) {
      if (!mounted) return;
      // Skip interrupt/resume narration updates for step tracking
      if (update.stepNumber == -1) {
        if (update.narrationText.isNotEmpty) {
          setState(() {
            _narrationLines.insert(0, update.narrationText);
            if (_narrationLines.length > 5) _narrationLines.removeLast();
          });
        }
        return;
      }
      setState(() {
        _currentStep = update.stepNumber;
        if (update.narrationText.isNotEmpty) {
          _narrationLines.insert(0, update.narrationText);
          if (_narrationLines.length > 5) _narrationLines.removeLast();
        }

        if (update.isComplete) {
          _isDone = true;
          _resultText = update.result ?? 'Task completed';

          // Update bubble to answer state (will hide pill, show bubble)
          final appState = context.read<AppStateProvider>();
          appState.updateBubbleState(BubbleState.answer);

          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              // Hide bubble when showing answer sheet
              appState.hideBubble();
              appState.setResult(
                TaskResult(
                  mode: 'agent',
                  title: _resultText,
                  details: update.resultDetails
                      ?.map(
                        (d) => TaskDetail(
                          icon: d['icon'] as String? ?? '✓',
                          text: d['text'] as String? ?? '',
                        ),
                      )
                      .toList(),
                ),
              );
            }
          });
        }

        if (update.isFailed) {
          _isFailed = true;
          _resultText = update.reason;
        }
      });
    });

    _agentLoop.startLoop(
      appPackage: widget.appPackage,
      goal: widget.goal,
      detectedLanguage: widget.detectedLanguage,
    );
  }

  /// Start recording voice during an interrupt.
  Future<void> _startInterruptRecording() async {
    final started = await _audioService.startRecording();
    if (!started) return;
    setState(() {
      _isRecording = true;
      _interruptTranscript = '...';
    });
  }

  /// Stop recording and process the interrupt voice.
  Future<void> _stopInterruptRecording() async {
    final wavPath = await _audioService.stopRecording();
    setState(() => _isRecording = false);

    if (wavPath == null) {
      _agentLoop.resumeAfterInterrupt();
      return;
    }

    setState(() => _interruptTranscript = 'Processing...');

    // Send to backend
    final response = await ApiService.processVoice(wavPath);
    if (!mounted) return;

    final mode = response['mode'] as String? ?? 'error';
    final transcript = response['transcript'] as String? ?? '';

    // Check if user wants to stop
    if (transcript.toLowerCase().contains('stop') ||
        transcript.toLowerCase().contains('रुको') ||
        transcript.toLowerCase().contains('बंद')) {
      _agentLoop.stopLoop();
      if (mounted) context.read<AppStateProvider>().goHome();
      return;
    }

    if (mode == 'answer') {
      final answer = response['answer'] as String? ?? '';
      final ttsText = response['tts_text'] as String? ?? answer;
      final lang = response['detected_language'] as String? ?? 'hi-IN';
      setState(() {
        _interruptTranscript = transcript;
        _interruptAnswer = answer;
      });

      // Play the answer audio
      if (ttsText.isNotEmpty) {
        await _audioService.streamTts(ttsText, lang);
      }

      // Wait a moment for user to hear, then resume
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _agentLoop.resumeAfterInterrupt();
    } else {
      // Not a question — just resume
      setState(() {
        _interruptTranscript = transcript;
        _interruptAnswer = 'Resuming task...';
      });
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) _agentLoop.resumeAfterInterrupt();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _interruptSubscription?.cancel();
    // Cancel any ongoing recording to clean up WebSocket
    if (_isRecording) {
      _audioService.cancelRecording();
    }
    _agentLoop.stopLoop();
    _agentLoop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Dotted ring in processing state ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: screenHeight * 0.45,
            child: Center(
              child: AnimatedDottedRing(
                state: _isInterrupted ? RingState.idle : RingState.processing,
              ),
            ),
          ),

          // ── Step counter ──
          Positioned(
            top: screenHeight * 0.38,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Text(
                  _isDone
                      ? '✓ Done'
                      : _isFailed
                      ? '✗ Failed'
                      : _isInterrupted
                      ? '⏸ Paused'
                      : 'Step $_currentStep / 15',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _isDone
                        ? const Color(0xFF34D399)
                        : _isFailed
                        ? const Color(0xFFF87171)
                        : _isInterrupted
                        ? const Color(0xFF60A5FA)
                        : Colors.white70,
                  ),
                ),
              ),
            ),
          ),

          // ── Narration lines ──
          Positioned(
            top: screenHeight * 0.46,
            left: 28,
            right: 28,
            bottom: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: _narrationLines.asMap().entries.map((entry) {
                final index = entry.key;
                final text = entry.value;
                final opacity = (1.0 - index * 0.25).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AnimatedOpacity(
                    opacity: opacity,
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: index == 0 ? 20 : 16,
                        fontWeight: index == 0
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: Colors.white.withValues(alpha: opacity),
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Bottom buttons ──
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Pause/Resume button (tap bubble equivalent on screen)
                  if (!_isDone && !_isFailed)
                    GestureDetector(
                      onTap: () {
                        if (_isInterrupted) {
                          _agentLoop.resumeAfterInterrupt();
                        } else {
                          _agentLoop.pauseForInterrupt();
                        }
                      },
                      child: Container(
                        width: 52,
                        height: 52,
                        margin: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isInterrupted
                              ? const Color(0xFF1E88E5)
                              : const Color(0xFF1A1A1A),
                          border: Border.all(
                            color: _isInterrupted
                                ? const Color(0xFF42A5F5)
                                : const Color(0xFF333333),
                          ),
                        ),
                        child: Icon(
                          _isInterrupted ? Icons.play_arrow : Icons.pause,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  // Stop button
                  GestureDetector(
                    onTap: () {
                      _agentLoop.stopLoop();
                      context.read<AppStateProvider>().goHome();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: const Color(0xFF333333)),
                      ),
                      child: Text(
                        'रुको / Stop',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Interrupt overlay (frosted glass, shows when bubble tapped) ──
          if (_isInterrupted)
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '⏸ Task Paused',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF60A5FA),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_interruptTranscript.isNotEmpty)
                          Text(
                            _interruptTranscript,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        if (_interruptAnswer.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _interruptAnswer,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        // Mic button for interrupt voice
                        GestureDetector(
                          onTap: _isRecording
                              ? _stopInterruptRecording
                              : _startInterruptRecording,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isRecording
                                  ? Colors.white
                                  : const Color(0xFF1A1A1A),
                              border: Border.all(
                                color: _isRecording
                                    ? Colors.white
                                    : const Color(0xFF444444),
                                width: 2,
                              ),
                              boxShadow: _isRecording
                                  ? [
                                      BoxShadow(
                                        color: Colors.white.withValues(
                                          alpha: 0.2,
                                        ),
                                        blurRadius: 16,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              _isRecording ? Icons.stop : Icons.mic,
                              color: _isRecording ? Colors.black : Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isRecording ? 'Tap to stop' : 'Ask a question',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Back button ──
          Positioned(
            top: topPadding + 12,
            left: 16,
            child: GestureDetector(
              onTap: () {
                _agentLoop.stopLoop();
                context.read<AppStateProvider>().goHome();
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1A1A1A),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Color(0xFF999999),
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
