import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import 'api_service.dart';

/// AudioService — handles microphone recording and audio playback.
/// Exposes amplitude for waveform widgets and isPlaying for orb animation.
class AudioService extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  WebSocketChannel? _wsChannel;

  bool _isRecording = false;
  bool _isPlaying = false;
  double _amplitude = 0.0;
  double _playbackAmplitude = 0.0;
  String? _lastRecordingPath;
  String _liveTranscript = '';
  Timer? _amplitudeTimer;
  Timer? _playbackPulseTimer;
  DateTime? _recordingStartTime;

  // ── Getters ──
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  double get amplitude => _amplitude;
  double get playbackAmplitude => _playbackAmplitude;
  String? get lastRecordingPath => _lastRecordingPath;
  String get liveTranscript => _liveTranscript;

  // ── Recording ──

  /// Start recording audio in WAV format at 16kHz mono.
  /// Returns false if permission denied.
  Future<bool> startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        debugPrint('AudioService: Microphone permission denied');
        return false;
      }

      // Close any existing WebSocket connection first
      _closeWebSocket();

      // Reset state
      _liveTranscript = '';
      _isRecording = true;
      _amplitude = 0.0;
      notifyListeners();

      // Prepare WAV saving path
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _lastRecordingPath = '${dir.path}/recording_$timestamp.wav';

      // Use file-based recording (reliable on all devices)
      const config = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      );

      await _recorder.start(config, path: _lastRecordingPath!);
      _recordingStartTime = DateTime.now();

      // Best-effort: open WebSocket for live transcript
      // If this fails, recording still works perfectly
      try {
        final wsUrl = ApiService.baseUrl.replaceFirst('http', 'ws');
        _wsChannel = IOWebSocketChannel.connect(
          Uri.parse('$wsUrl/stt_stream?language_code=unknown'),
        );

        _wsChannel!.stream.listen(
          (message) {
            try {
              final data = jsonDecode(message);
              if (data['transcript'] != null) {
                _liveTranscript = data['transcript'];
                notifyListeners();
              }
            } catch (_) {}
          },
          onError: (e) {
            debugPrint('AudioService: WebSocket stream error: $e');
            _wsChannel = null;
          },
        );
      } catch (e) {
        debugPrint('AudioService: WebSocket connect failed (non-blocking): $e');
        _wsChannel = null;
      }

      // Poll amplitude
      _amplitudeTimer?.cancel();
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (
        _,
      ) async {
        try {
          final amp = await _recorder.getAmplitude();
          final dB = amp.current;
          if (dB == double.negativeInfinity || dB < -60) {
            _amplitude = 0.0;
          } else {
            _amplitude = ((dB + 60) / 60).clamp(0.0, 1.0);
          }
          if (DateTime.now().millisecond < 100) {
            debugPrint('AudioService: dB=$dB, amplitude=$_amplitude');
          }
          notifyListeners();
        } catch (_) {}
      });

      return true;
    } catch (e) {
      debugPrint('AudioService: startRecording error: $e');
      return false;
    }
  }

  /// Stop recording and return the file path of the saved WAV.
  /// Enforces a minimum recording duration of 1.5s so STT has enough audio.
  Future<String?> stopRecording() async {
    try {
      // Enforce minimum recording duration for Sarvam STT
      if (_recordingStartTime != null) {
        final elapsed = DateTime.now().difference(_recordingStartTime!);
        if (elapsed.inMilliseconds < 1500) {
          final remaining = 1500 - elapsed.inMilliseconds;
          await Future.delayed(Duration(milliseconds: remaining));
        }
      }

      _amplitudeTimer?.cancel();
      _amplitudeTimer = null;

      // Stop the recorder (file is finalized automatically)
      final path = await _recorder.stop();

      // Close WebSocket if open (with proper cleanup)
      _closeWebSocket();

      _isRecording = false;
      _amplitude = 0.0;
      _recordingStartTime = null;
      notifyListeners();

      // Use the path from recorder, or fall back to our stored path
      final finalPath = path ?? _lastRecordingPath;
      debugPrint('AudioService: Recording saved to: $finalPath');
      _lastRecordingPath = finalPath;
      return finalPath;
    } catch (e) {
      debugPrint('AudioService: stopRecording error: $e');
      _closeWebSocket();
      _isRecording = false;
      _amplitude = 0.0;
      _recordingStartTime = null;
      notifyListeners();
      return _lastRecordingPath;
    }
  }

  /// Close WebSocket connection safely
  void _closeWebSocket() {
    try {
      if (_wsChannel != null) {
        _wsChannel!.sink.close();
        debugPrint('AudioService: WebSocket closed');
      }
    } catch (e) {
      debugPrint('AudioService: Error closing WebSocket: $e');
    }
    _wsChannel = null;
  }

  /// Cancel any ongoing recording (useful when user navigates away)
  Future<void> cancelRecording() async {
    debugPrint('AudioService: Canceling recording');
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _closeWebSocket();

    try {
      await _recorder.stop();
    } catch (_) {}

    _isRecording = false;
    _amplitude = 0.0;
    _recordingStartTime = null;
    _liveTranscript = '';
    notifyListeners();
  }

  /// Stream TTS audio from backend, save to temp file, and play.
  Future<void> streamTts(String text, String languageCode) async {
    try {
      if (text.isEmpty) return;

      _isPlaying = true;
      notifyListeners();

      // Start pulsing amplitude for orb animation
      _startPlaybackPulse();

      final audioBytes = await ApiService.downloadTts(text, languageCode);
      if (audioBytes != null && audioBytes.isNotEmpty) {
        debugPrint('AudioService: TTS received ${audioBytes.length} bytes');

        // Save to temp file and play
        final dir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = '${dir.path}/tts_stream_$timestamp.wav';
        final file = File(filePath);
        await file.writeAsBytes(audioBytes);

        await _player.setFilePath(filePath);
        await _player.play();

        // Wait for playback to complete
        await _player.playerStateStream.firstWhere(
          (state) => state.processingState == ProcessingState.completed,
        );

        // Cleanup
        try {
          file.deleteSync();
        } catch (_) {}
      } else {
        debugPrint('AudioService: TTS download returned null/empty');
      }
    } catch (e) {
      debugPrint('AudioService: streamTts error: $e');
    } finally {
      _stopPlaybackPulse();
      _isPlaying = false;
      _playbackAmplitude = 0.0;
      notifyListeners();
    }
  }

  /// (Legacy) Play audio from a base64-encoded string.
  Future<void> playAudio(String base64Audio) async {
    try {
      if (base64Audio.isEmpty) return;

      // Decode base64 to bytes and write to temp file
      final bytes = base64Decode(base64Audio);
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${dir.path}/tts_$timestamp.wav';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      await _player.setFilePath(filePath);
      _isPlaying = true;
      notifyListeners();

      // Simulate playback amplitude pulsing for orb animation
      _startPlaybackPulse();

      _player.play();

      // Listen for completion
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _stopPlaybackPulse();
          _isPlaying = false;
          _playbackAmplitude = 0.0;
          notifyListeners();

          // Cleanup temp file
          try {
            file.deleteSync();
          } catch (_) {}
        }
      });
    } catch (e) {
      debugPrint('AudioService: playAudio error: $e');
      _isPlaying = false;
      _playbackAmplitude = 0.0;
      notifyListeners();
    }
  }

  /// Stop audio playback.
  Future<void> stopAudio() async {
    try {
      await _player.stop();
      _stopPlaybackPulse();
      _isPlaying = false;
      _playbackAmplitude = 0.0;
      notifyListeners();
    } catch (e) {
      debugPrint('AudioService: stopAudio error: $e');
    }
  }

  void _startPlaybackPulse() {
    _playbackPulseTimer?.cancel();
    final rng = Random();
    _playbackPulseTimer = Timer.periodic(const Duration(milliseconds: 120), (
      _,
    ) {
      // Simulate natural speech amplitude variation
      _playbackAmplitude = 0.3 + rng.nextDouble() * 0.5;
      notifyListeners();
    });
  }

  void _stopPlaybackPulse() {
    _playbackPulseTimer?.cancel();
    _playbackPulseTimer = null;
  }

  // ── Cleanup ──

  @override
  void dispose() {
    _amplitudeTimer?.cancel();
    _playbackPulseTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }
}
