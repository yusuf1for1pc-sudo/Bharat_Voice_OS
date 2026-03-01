import 'dart:ui';
import '../widgets/voice_waveform.dart';
import '../widgets/ai_voice_orb.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../models/app_state.dart';
import '../widgets/animated_dotted_ring.dart';
import '../services/audio_service.dart';
import '../services/api_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

/// Unified voice-chat screen:
///   Idle    → orb centered + mic button at bottom
///   Listen  → orb reacts, waveform visualizer above mic, transcript shows
///   Confirm → language flashcard overlay
///   Answer  → orb shrinks to top, frosted sheet slides up from bottom
class VoiceChatScreen extends StatefulWidget {
  const VoiceChatScreen({super.key});

  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen>
    with TickerProviderStateMixin {
  // Sheet slide animation
  late AnimationController _sheetController;
  late Animation<double> _sheetAnimation;

  // Mic pulse animation
  late AnimationController _micPulseController;

  // Voice level for waveform (from real mic or AI playback)
  double _voiceLevel = 0.0;
  bool _aiSpeaking = false;

  // Language flashcard animation
  late AnimationController _flashcardController;
  late Animation<double> _flashcardAnimation;

  // Orb position animation (moves orb up when answering)
  late AnimationController _orbTransitionController;
  late Animation<double> _orbTransition;

  // ── Real services ──
  final AudioService _audioService = AudioService();
  Map<String, dynamic>? _lastApiResponse;

  _VoiceStage _stage = _VoiceStage.idle;
  String _transcript = '';
  String _answerText = '';
  String _detectedLanguage = '';
  bool _languageConfirmed = false;
  String _lastTtsText = '';
  String _lastTtsLang = 'hi-IN';

  @override
  void initState() {
    super.initState();
    _sheetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _sheetAnimation = CurvedAnimation(
      parent: _sheetController,
      curve: Curves.easeOutCubic,
    );

    _micPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _flashcardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flashcardAnimation = CurvedAnimation(
      parent: _flashcardController,
      curve: Curves.easeOutBack,
    );

    _orbTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _orbTransition = CurvedAnimation(
      parent: _orbTransitionController,
      curve: Curves.easeInOutCubic,
    );

    // Listen to AudioService amplitude changes for real waveform
    _audioService.addListener(_onAudioServiceChanged);
  }

  void _onAudioServiceChanged() {
    if (!mounted) return;
    setState(() {
      if (_audioService.isRecording) {
        _voiceLevel = _audioService.amplitude;
        if (_audioService.liveTranscript.isNotEmpty) {
          _transcript = _audioService.liveTranscript;
        }
      } else if (_audioService.isPlaying) {
        _voiceLevel = _audioService.playbackAmplitude;
      }
    });
  }

  @override
  void dispose() {
    _audioService.removeListener(_onAudioServiceChanged);
    _audioService.dispose();
    _sheetController.dispose();
    _micPulseController.dispose();
    _flashcardController.dispose();
    _orbTransitionController.dispose();
    super.dispose();
  }

  void _onMicTap() {
    if (_stage == _VoiceStage.idle) {
      setState(() {
        _stage = _VoiceStage.listening;
        _transcript = '';
        _answerText = '';
      });
      _micPulseController.repeat(reverse: true);
      _sheetController.reverse();
      _orbTransitionController.reverse();
      _startRealListening();
    } else if (_stage == _VoiceStage.listening) {
      _stopAndProcess();
    } else if (_stage == _VoiceStage.answering) {
      _resetToIdle();
    }
  }

  /// Cancel recording — discard audio and return to idle.
  void _cancelRecording() async {
    _micPulseController.stop();
    _micPulseController.reset();
    await _audioService.stopRecording(); // stop but discard
    setState(() {
      _stage = _VoiceStage.idle;
      _transcript = '';
      _voiceLevel = 0.0;
    });
  }

  /// Launch floating bubble over all apps.
  Future<void> _launchBubble() async {
    // Request overlay permission
    if (!await Permission.systemAlertWindow.isGranted) {
      final status = await Permission.systemAlertWindow.request();
      if (!status.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable "Display over other apps" permission'),
          ),
        );
        return;
      }
    }

    // Set up bubble event handlers
    _setupBubbleEventHandlers();

    // Start the floating bubble service
    if (mounted) {
      final appState = context.read<AppStateProvider>();
      await appState.showBubble();
    }
  }

  /// Set up handlers for bubble events
  void _setupBubbleEventHandlers() {
    const bubbleEventsChannel = MethodChannel('bharat_voice_os/bubble_events');
    bubbleEventsChannel.setMethodCallHandler((call) async {
      if (!mounted) return;

      switch (call.method) {
        case 'onBubbleStartListening':
          // Bubble tapped in idle mode - start listening
          if (_stage == _VoiceStage.idle) {
            _onMicTap();
            // Update bubble to listening state
            final appState = context.read<AppStateProvider>();
            await appState.updateBubbleState(BubbleState.listening);
          }
          break;

        case 'onBubbleStopListening':
          // Bubble tapped in listening mode - stop and process
          if (_stage == _VoiceStage.listening) {
            _stopAndProcess();
            // Update bubble to idle (will change to working if agent mode)
            final appState = context.read<AppStateProvider>();
            await appState.updateBubbleState(BubbleState.idle);
          }
          break;

        case 'onBubbleTap':
          // Legacy handler - start listening if idle
          if (_stage == _VoiceStage.idle) {
            _onMicTap();
          }
          break;

        case 'onBubbleStop':
          // Forward to app state for agent mode handling
          context.read<AppStateProvider>().handleBubbleEvent(BubbleEvent.stop);
          break;

        case 'onBubblePause':
          context.read<AppStateProvider>().handleBubbleEvent(BubbleEvent.pause);
          break;

        case 'onBubbleResume':
          context.read<AppStateProvider>().handleBubbleEvent(
            BubbleEvent.resume,
          );
          break;

        case 'onBubbleAsk':
          context.read<AppStateProvider>().handleBubbleEvent(BubbleEvent.ask);
          break;
      }
    });
  }

  /// Start real microphone recording via AudioService.
  Future<void> _startRealListening() async {
    final started = await _audioService.startRecording();
    if (!started) {
      if (!mounted) return;
      setState(() {
        _transcript = 'Microphone permission denied';
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _resetToIdle();
      return;
    }
    // Transcript will be updated via _onAudioUpdate listening to liveTranscript
    setState(() {
      _transcript = '...';
    });
  }

  /// Stop recording and send to backend for processing.
  Future<void> _stopAndProcess() async {
    _micPulseController.stop();
    final wavPath = await _audioService.stopRecording();
    if (wavPath == null || !mounted) {
      _resetToIdle();
      return;
    }

    // Show processing state
    setState(() {
      _stage = _VoiceStage.answering;
      _voiceLevel = 0.0;
      _answerText = 'Processing...';
    });
    _orbTransitionController.forward();
    _sheetController.forward();

    // Call backend
    final response = await ApiService.processVoice(wavPath);
    if (!mounted) return;

    _lastApiResponse = response;
    final mode = response['mode'] as String? ?? 'error';
    final transcript = response['transcript'] as String? ?? '';
    final langCode = response['detected_language'] as String? ?? 'hi-IN';

    if (mode == 'error') {
      setState(() {
        _answerText = response['error'] as String? ?? 'Something went wrong.';
        _transcript = transcript;
      });
      return;
    }

    // Convert language code to display name
    final langDisplay = _languageCodeToName(langCode);

    setState(() {
      _transcript = transcript;
      _detectedLanguage = langDisplay;
    });

    // Show language flashcard on first interaction
    if (!_languageConfirmed) {
      _showLanguageFlashcard(langDisplay);
      return;
    }

    // Route based on mode
    _handleApiResponse(response);
  }

  void _showLanguageFlashcard(String language) {
    _micPulseController.stop();
    setState(() => _voiceLevel = 0.0);
    setState(() {
      _stage = _VoiceStage.languageConfirm;
      _detectedLanguage = language;
    });
    _flashcardController.forward(from: 0);
  }

  void _confirmLanguage() {
    _flashcardController.reverse();
    setState(() {
      _languageConfirmed = true;
    });
    // Now handle the stored API response
    if (_lastApiResponse != null) {
      _handleApiResponse(_lastApiResponse!);
    } else {
      _resetToIdle();
    }
  }

  /// Route based on API response mode.
  Future<void> _handleApiResponse(Map<String, dynamic> response) async {
    final mode = response['mode'] as String? ?? 'error';
    final ttsText = response['tts_text'] as String? ?? '';
    final audioB64 = response['audio_base64'] as String? ?? '';
    final detectedLanguage =
        response['detected_language'] as String? ?? 'hi-IN';
    final appState = context.read<AppStateProvider>();

    switch (mode) {
      case 'answer':
        final answer = response['answer'] as String? ?? '';
        debugPrint('VoiceChatScreen: answer=$answer, ttsText=$ttsText');
        setState(() {
          _stage = _VoiceStage.answering;
          _answerText = answer.isNotEmpty ? answer : ttsText;
          _lastTtsText = ttsText.isNotEmpty ? ttsText : answer;
          _lastTtsLang = detectedLanguage;
        });
        _orbTransitionController.forward();
        _sheetController.forward();

        if (ttsText.isNotEmpty) {
          _streamRealAudio(ttsText, detectedLanguage);
        } else if (audioB64.isNotEmpty) {
          _playRealAudio(audioB64);
        }
        break;

      case 'confirm':
        // Navigate to confirmation screen
        appState.setResult(TaskResult.fromJson(response));
        if (ttsText.isNotEmpty) {
          _audioService.streamTts(ttsText, detectedLanguage);
        } else if (audioB64.isNotEmpty) {
          _audioService.playAudio(audioB64);
        }
        break;

      case 'agent_start':
        // Check Accessibility Service is enabled first
        try {
          const accChannel = MethodChannel('bharat_voice_os/accessibility');
          final isEnabled =
              await accChannel.invokeMethod<bool>('isAccessibilityEnabled') ??
              false;
          if (!isEnabled) {
            setState(() {
              _answerText =
                  'Accessibility Service is required for the agent. Opening Settings — please enable "Bharat Voice OS".';
              _stage = _VoiceStage.answering;
            });
            _sheetController.forward();
            // Open accessibility settings
            try {
              await accChannel.invokeMethod('openAccessibilitySettings');
            } catch (_) {}
            return;
          }
        } catch (_) {}

        // Request System Alert Window permission for floating bubble
        if (!await Permission.systemAlertWindow.isGranted) {
          final status = await Permission.systemAlertWindow.request();
          if (!status.isGranted) {
            setState(() {
              _answerText =
                  'Please enable "Display over other apps" permission to use the agent.';
              _stage = _VoiceStage.answering;
            });
            return;
          }
        }

        // Navigate to agent mode screen
        final appPackage = response['app_package'] as String? ?? '';
        final goal = response['goal'] as String? ?? '';

        appState.startAgentMode(
          appPackage: appPackage,
          goal: goal,
          language: detectedLanguage,
        );
        if (ttsText.isNotEmpty) {
          _audioService.streamTts(ttsText, detectedLanguage);
        } else if (audioB64.isNotEmpty) {
          _audioService.playAudio(audioB64);
        }
        break;

      default:
        setState(() {
          _answerText = response['error'] as String? ?? 'Something went wrong.';
        });
    }
  }

  /// Play real TTS audio from base64 and animate the orb.
  Future<void> _playRealAudio(String base64Audio) async {
    setState(() => _aiSpeaking = true);
    await _audioService.playAudio(base64Audio);
    while (_audioService.isPlaying && mounted) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (!mounted) return;
    setState(() {
      _aiSpeaking = false;
      _voiceLevel = 0.0;
    });
  }

  /// Stream real TTS audio from backend text and animate the orb.
  Future<void> _streamRealAudio(String text, String lang) async {
    setState(() => _aiSpeaking = true);
    await _audioService.streamTts(text, lang);
    // Wait for playback to finish
    while (_audioService.isPlaying && mounted) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (!mounted) return;
    setState(() {
      _aiSpeaking = false;
      _voiceLevel = 0.0;
    });
  }

  /// Replay the last TTS audio when user taps the speaker button.
  void _replayAudio() {
    if (_lastTtsText.isNotEmpty) {
      _streamRealAudio(_lastTtsText, _lastTtsLang);
    }
  }

  /// Convert language code to display name.
  String _languageCodeToName(String code) {
    const names = {
      'hi-IN': 'Hindi',
      'en-IN': 'English',
      'mr-IN': 'Marathi',
      'ta-IN': 'Tamil',
      'te-IN': 'Telugu',
      'bn-IN': 'Bengali',
      'gu-IN': 'Gujarati',
      'kn-IN': 'Kannada',
      'ml-IN': 'Malayalam',
      'pa-IN': 'Punjabi',
      'or-IN': 'Odia',
    };
    return names[code] ?? code;
  }

  void _resetToIdle() {
    _sheetController.reverse();
    _orbTransitionController.reverse();
    _micPulseController.stop();
    _audioService.stopAudio();
    _audioService.stopRecording();
    setState(() {
      _voiceLevel = 0.0;
      _aiSpeaking = false;
      _stage = _VoiceStage.idle;
      _transcript = '';
      _answerText = '';
      _lastApiResponse = null;
    });
  }

  RingState get _ringState {
    switch (_stage) {
      case _VoiceStage.idle:
        return RingState.idle;
      case _VoiceStage.listening:
        return RingState.listening;
      case _VoiceStage.languageConfirm:
        return RingState.idle;
      case _VoiceStage.answering:
        return RingState.active;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ─── ORB ───
          // Animates from center of screen (idle) to top portion (answering)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _orbTransition,
              builder: (context, child) {
                // idle: orb centered vertically in top 55%
                // answering: orb in top 38%, scaled down to 0.6
                final orbAreaHeight =
                    screenHeight * (0.55 - 0.17 * _orbTransition.value);
                final orbScale = 1.0 - 0.4 * _orbTransition.value;

                return SizedBox(
                  width: double.infinity,
                  height: orbAreaHeight,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Show AiVoiceOrb when AI is answering, DottedRing otherwise
                      _stage == _VoiceStage.answering
                          ? AiVoiceOrb(
                              voiceLevel: _voiceLevel,
                              size: orbAreaHeight * 0.8 * orbScale,
                              color: Colors.white,
                            )
                          : Transform.scale(
                              scale: orbScale,
                              child: AnimatedDottedRing(state: _ringState),
                            ),
                      // Center label
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _stage == _VoiceStage.idle
                            ? Text(
                                'SPEAK TO BEGIN',
                                key: const ValueKey('idle'),
                                style: const TextStyle(
                                  fontFamily: 'SpaceMono',
                                  fontSize: 14,
                                  color: Colors.white,
                                  letterSpacing: 2,
                                ),
                              )
                            : _stage == _VoiceStage.listening
                            ? Text(
                                'LISTENING...',
                                key: const ValueKey('listen'),
                                style: const TextStyle(
                                  fontFamily: 'SpaceMono',
                                  fontSize: 14,
                                  color: Colors.white,
                                  letterSpacing: 2,
                                ),
                              )
                            : const SizedBox.shrink(key: ValueKey('other')),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // ─── Listening transcript (between orb and mic area) ───
          if (_stage == _VoiceStage.listening)
            Positioned(
              top: screenHeight * 0.48,
              left: 32,
              right: 32,
              bottom: 180,
              child: Center(
                child: Text(
                  _transcript.isEmpty ? '...' : _transcript,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
              ),
            ),

          // ─── Waveform + Mic (bottom area, visible in idle & listening) ───
          if (_stage == _VoiceStage.idle || _stage == _VoiceStage.listening)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 160,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Waveform visualizer (only during listening)
                  if (_stage == _VoiceStage.listening)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: VoiceWaveform(
                        voiceLevel: _voiceLevel,
                        width: 140,
                        height: 40,
                        barCount: 11,
                        color: Colors.white,
                      ),
                    ),
                  // Mic / Stop button + Bubble button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Bubble launch button (only when idle)
                      if (_stage == _VoiceStage.idle)
                        GestureDetector(
                          onTap: _launchBubble,
                          child: Container(
                            width: 48,
                            height: 48,
                            margin: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.15),
                                  Colors.white.withValues(alpha: 0.05),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: const Icon(
                              Icons.auto_awesome,
                              color: Colors.white70,
                              size: 22,
                            ),
                          ),
                        ),
                      // Cancel button (only during listening)
                      if (_stage == _VoiceStage.listening)
                        GestureDetector(
                          onTap: _cancelRecording,
                          child: Container(
                            width: 48,
                            height: 48,
                            margin: const EdgeInsets.only(right: 24),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.1),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                              size: 24,
                            ),
                          ),
                        ),
                      // Mic / Stop button
                      GestureDetector(
                        onTap: _onMicTap,
                        child: AnimatedBuilder(
                          animation: _micPulseController,
                          builder: (context, child) {
                            final scale = _stage == _VoiceStage.listening
                                ? 1.0 + _micPulseController.value * 0.12
                                : 1.0;
                            return Transform.scale(
                              scale: scale,
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _stage == _VoiceStage.listening
                                      ? Colors.white
                                      : const Color(0xFF1A1A1A),
                                  border: Border.all(
                                    color: _stage == _VoiceStage.listening
                                        ? Colors.white
                                        : const Color(0xFF333333),
                                    width: 2,
                                  ),
                                  boxShadow: _stage == _VoiceStage.listening
                                      ? [
                                          BoxShadow(
                                            color: Colors.white.withValues(
                                              alpha: 0.25,
                                            ),
                                            blurRadius: 24,
                                            spreadRadius: 4,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Icon(
                                  _stage == _VoiceStage.listening
                                      ? Icons.stop_rounded
                                      : Icons.mic,
                                  color: _stage == _VoiceStage.listening
                                      ? Colors.black
                                      : Colors.white,
                                  size: 32,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // ─── Answer bottom sheet (frosted glass, Image 3 style) ───
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _sheetAnimation,
              builder: (context, child) {
                final sheetHeight = screenHeight * 0.62 * _sheetAnimation.value;
                if (sheetHeight < 1) return const SizedBox.shrink();
                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(
                      height: sheetHeight,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.06),
                            Colors.white.withValues(alpha: 0.12),
                            Colors.white.withValues(alpha: 0.20),
                          ],
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      child: ClipRect(
                        child: sheetHeight > 200
                            ? Opacity(
                                opacity: _sheetAnimation.value.clamp(0.0, 1.0),
                                child: Column(
                                  children: [
                                    const SizedBox(height: 12),
                                    // Pill bar: X | "Listening..." | speaker
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      child: Container(
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.06,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const SizedBox(width: 8),
                                            GestureDetector(
                                              onTap: _resetToIdle,
                                              child: _pillCircle(Icons.close),
                                            ),
                                            const Spacer(),
                                            Text(
                                              _aiSpeaking
                                                  ? 'Speaking...'
                                                  : 'Done',
                                              style: GoogleFonts.inter(
                                                fontSize: 15,
                                                color: Colors.white70,
                                              ),
                                            ),
                                            const Spacer(),
                                            _pillCircle(Icons.settings),
                                            const SizedBox(width: 8),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    // Question text (Transcript)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 28,
                                      ),
                                      child: Text(
                                        _transcript,
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w400,
                                          color: Colors.white60,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    // Answer text
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 28,
                                        ),
                                        child: SingleChildScrollView(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _answerText,
                                                style: GoogleFonts.inter(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.white,
                                                  height: 1.5,
                                                ),
                                              ),
                                              if (_answerText.isNotEmpty &&
                                                  !_aiSpeaking)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 16,
                                                      ),
                                                  child: GestureDetector(
                                                    onTap: _replayAudio,
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 14,
                                                            vertical: 8,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white
                                                            .withValues(
                                                              alpha: 0.1,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              20,
                                                            ),
                                                        border: Border.all(
                                                          color: Colors.white
                                                              .withValues(
                                                                alpha: 0.15,
                                                              ),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          const Icon(
                                                            Icons
                                                                .volume_up_rounded,
                                                            color:
                                                                Colors.white70,
                                                            size: 18,
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Text(
                                                            'Replay',
                                                            style:
                                                                GoogleFonts.inter(
                                                                  fontSize: 13,
                                                                  color: Colors
                                                                      .white70,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Mic button — tap to continue conversation
                                    GestureDetector(
                                      onTap: () {
                                        _sheetController.reverse();
                                        _orbTransitionController.reverse();
                                        setState(() {
                                          _stage = _VoiceStage.listening;
                                          _transcript = '';
                                          _aiSpeaking = false;
                                        });
                                        _micPulseController.repeat(
                                          reverse: true,
                                        );
                                        _startRealListening();
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 24,
                                        ),
                                        child: Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white.withValues(
                                              alpha: 0.12,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.2,
                                              ),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.mic,
                                            color: Colors.white,
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ─── Language confirmation flashcard ───
          if (_stage == _VoiceStage.languageConfirm)
            Positioned.fill(
              child: GestureDetector(
                onTap: _confirmLanguage,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.6),
                  child: Center(
                    child: ScaleTransition(
                      scale: _flashcardAnimation,
                      child: Container(
                        width: 300,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFF333333),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.05),
                              blurRadius: 40,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              child: const Center(
                                child: Text(
                                  '🗣️',
                                  style: TextStyle(fontSize: 28),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _detectedLanguage,
                              style: GoogleFonts.inter(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _getLanguageNative(_detectedLanguage),
                              style: GoogleFonts.inter(
                                fontSize: 20,
                                color: const Color(0xFF999999),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Is this your language?',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: const Color(0xFF666666),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      _flashcardController.reverse();
                                      _resetToIdle();
                                    },
                                    child: Container(
                                      height: 48,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: const Color(0xFF333333),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'नहीं',
                                          style: GoogleFonts.inter(
                                            fontSize: 15,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: _confirmLanguage,
                                    child: Container(
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'हाँ',
                                          style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ─── Top-left: history button ───
          Positioned(
            top: topPadding + 12,
            left: 16,
            child: GestureDetector(
              onTap: () => context.read<AppStateProvider>().navigateTo(
                AppScreen.history,
              ),
              child: _navCircle(Icons.menu),
            ),
          ),

          // ─── Top-right: settings button ───
          Positioned(
            top: topPadding + 12,
            right: 16,
            child: GestureDetector(
              onTap: () {
                // TODO: Open settings page
              },
              child: _navCircle(Icons.settings),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navCircle(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Icon(icon, color: const Color(0xFF999999), size: 20),
    );
  }

  Widget _pillCircle(IconData icon) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.12),
      ),
      child: Icon(icon, color: Colors.white70, size: 18),
    );
  }

  String _getLanguageNative(String lang) {
    switch (lang.toLowerCase()) {
      case 'hindi':
        return 'हिन्दी';
      case 'tamil':
        return 'தமிழ்';
      case 'telugu':
        return 'తెలుగు';
      case 'bengali':
        return 'বাংলা';
      case 'marathi':
        return 'मराठी';
      case 'gujarati':
        return 'ગુજરાતી';
      case 'kannada':
        return 'ಕನ್ನಡ';
      case 'malayalam':
        return 'മലയാളം';
      case 'punjabi':
        return 'ਪੰਜਾਬੀ';
      case 'odia':
        return 'ଓଡ଼ିଆ';
      default:
        return lang;
    }
  }
}

enum _VoiceStage { idle, listening, languageConfirm, answering }
