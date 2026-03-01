import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

/// ApiService — handles all HTTP communication with the FastAPI backend.
class ApiService {
  static String get baseUrl => AppConfig.backendUrl;

  /// Download TTS audio bytes from backend.
  /// Returns raw audio bytes or null if failed.
  static Future<Uint8List?> downloadTts(String text, String languageCode) async {
    try {
      final uri = Uri.parse('$baseUrl/tts_stream').replace(
        queryParameters: {
          'text': text,
          'language_code': languageCode,
        },
      );
      final response = await http.get(uri).timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        debugPrint('ApiService: TTS downloaded ${response.bodyBytes.length} bytes');
        return response.bodyBytes;
      }
      debugPrint('ApiService: TTS failed status=${response.statusCode} bodyLen=${response.bodyBytes.length}');
      return null;
    } catch (e) {
      debugPrint('ApiService: downloadTts exception: $e');
      return null;
    }
  }

  /// Send recorded voice WAV to backend /process endpoint.
  /// Returns parsed JSON response map or error map.
  static Future<Map<String, dynamic>> processVoice(String audioFilePath) async {
    try {
      final uri = Uri.parse('$baseUrl/process');
      final request = http.MultipartRequest('POST', uri);

      request.files.add(
        await http.MultipartFile.fromPath('file', audioFilePath),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('ApiService: processVoice error ${response.statusCode}: ${response.body}');
        return {
          'mode': 'error',
          'error': 'Server error. Please try again.',
          'transcript': '',
          'detected_language': 'hi-IN',
        };
      }
    } on SocketException {
      return {
        'mode': 'error',
        'error': 'Network nahi hai, baad mein try karein.',
        'transcript': '',
        'detected_language': 'hi-IN',
      };
    } catch (e) {
      debugPrint('ApiService: processVoice exception: $e');
      return {
        'mode': 'error',
        'error': 'Network nahi hai, baad mein try karein.',
        'transcript': '',
        'detected_language': 'hi-IN',
      };
    }
  }

  /// Send screenshot + goal + history to /agent_step for vision agent.
  /// Returns parsed action JSON map.
  static Future<Map<String, dynamic>> agentStep({
    required String screenshotBase64,
    required String goal,
    required List<Map<String, dynamic>> history,
    required int stepNumber,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/agent_step');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'screenshot_base64': screenshotBase64,
          'goal': goal,
          'history': history,
          'step_number': stepNumber,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        return {'action': 'failed', 'reason': 'Server error ${response.statusCode}'};
      }
    } on SocketException {
      return {'action': 'failed', 'reason': 'Network not available'};
    } catch (e) {
      debugPrint('ApiService: agentStep exception: $e');
      return {'action': 'failed', 'reason': 'Network error: $e'};
    }
  }

  /// Resolve app name to Android package name via /open_app.
  static Future<String?> openApp(String appName) async {
    try {
      final uri = Uri.parse('$baseUrl/open_app');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'app_name': appName}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['package'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('ApiService: openApp exception: $e');
      return null;
    }
  }

  /// Confirm a pending action via /confirm endpoint.
  /// Returns parsed response map with agent_start mode.
  static Future<Map<String, dynamic>> confirmAction(
    Map<String, dynamic> intentData,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/confirm');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'intent_data': intentData}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        return {
          'mode': 'error',
          'error': 'Server error ${response.statusCode}',
        };
      }
    } on SocketException {
      return {
        'mode': 'error',
        'error': 'Network nahi hai, baad mein try karein.',
      };
    } catch (e) {
      debugPrint('ApiService: confirmAction exception: $e');
      return {
        'mode': 'error',
        'error': 'Network error',
      };
    }
  }
}
