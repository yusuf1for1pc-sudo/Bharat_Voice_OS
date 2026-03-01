import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Callback type for step updates
typedef StepCallback = void Function(int step, String description);

/// HardcodedFlowService — fast-path demo flows that bypass the vision loop.
/// Uses hardcoded pixel coordinates for reliable demo execution.
class HardcodedFlowService {
  static const _channel = MethodChannel('bharat_voice_os/accessibility');
  static const _bubbleChannel = MethodChannel('bharat_voice_os/bubble');

  /// Hide the floating pill/bubble to avoid blocking taps and screenshots
  static Future<void> _hideOverlay() async {
    try {
      await _bubbleChannel.invokeMethod('setOverlayVisibility', {
        'visible': false,
      });
      await Future.delayed(
        const Duration(milliseconds: 100),
      ); // Wait for overlay to hide
    } catch (e) {
      debugPrint('HardcodedFlow: hideOverlay error: $e');
    }
  }

  /// Show the floating pill/bubble again
  static Future<void> _showOverlay() async {
    try {
      await _bubbleChannel.invokeMethod('setOverlayVisibility', {
        'visible': true,
      });
    } catch (e) {
      debugPrint('HardcodedFlow: showOverlay error: $e');
    }
  }

  /// Execute a tap gesture at specific coordinates
  static Future<bool> _tap(int x, int y) async {
    try {
      await _channel.invokeMethod('executeGesture', {
        'params': {'action': 'tap', 'x': x, 'y': y},
      });
      return true;
    } catch (e) {
      debugPrint('HardcodedFlow: tap error at ($x, $y): $e');
      return false;
    }
  }

  /// Execute a type gesture (types text into focused field)
  static Future<bool> _type(String text) async {
    try {
      await _channel.invokeMethod('executeGesture', {
        'params': {'action': 'type', 'text': text},
      });
      return true;
    } catch (e) {
      debugPrint('HardcodedFlow: type error: $e');
      return false;
    }
  }

  /// Wait for a specified duration
  static Future<void> _wait(int milliseconds) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
  }

  /// Send a WhatsApp message using hardcoded coordinates.
  /// Coordinates calibrated for 1080x2400 screen.
  ///
  /// Flow:
  /// 1. Tap search icon (540, 270)
  /// 2. Type contact name
  /// 3. Tap first search result (540, 500)
  /// 4. Tap message input (470, 2200)
  /// 5. Type message
  /// 6. Tap send button (1010, 2200)
  static Future<bool> sendWhatsAppMessage({
    required String contactName,
    required String message,
    StepCallback? onStep,
  }) async {
    try {
      debugPrint(
        'HardcodedFlow: Starting WhatsApp flow - Contact: $contactName, Message: $message',
      );

      // Pill is positioned on right side (x=900+) so it won't block center taps (x=540)
      // No need to hide overlay

      // Step 1: Tap search bar "Ask Meta AI or Search"
      onStep?.call(1, 'Tapping search...');
      await _tap(360, 150);
      await _wait(800);

      // Step 2: Type contact name
      onStep?.call(2, 'Typing $contactName...');
      await _type(contactName);
      await _wait(1200);

      // Step 3: Tap first search result (the contact)
      onStep?.call(3, 'Selecting $contactName...');
      await _tap(540, 500);
      await _wait(1000);

      // Step 4: Tap message input field
      onStep?.call(4, 'Focusing message box...');
      await _tap(470, 2200);
      await _wait(500);

      // Step 5: Type the message (in whatever language user spoke)
      onStep?.call(5, 'Typing message...');
      await _type(message);
      await _wait(500);

      // Step 6: Tap send button
      onStep?.call(6, 'Sending message...');
      await _tap(1010, 2200);
      await _wait(500);

      // DON'T restore overlay - let user see WhatsApp chat
      // await _showOverlay();

      debugPrint('HardcodedFlow: WhatsApp message sent successfully!');
      return true;
    } catch (e) {
      debugPrint('HardcodedFlow: sendWhatsAppMessage error: $e');
      // Don't restore overlay on error either
      return false;
    }
  }

  /// Check if a goal matches WhatsApp messaging pattern.
  /// Returns parsed {contact, message} or null if not a match.
  static Map<String, String>? parseWhatsAppGoal(String goal) {
    final goalLower = goal.toLowerCase();

    // Check if this is a WhatsApp message request
    if (!goalLower.contains('whatsapp') &&
        !goalLower.contains('message') &&
        !goalLower.contains('send')) {
      return null;
    }

    String? contact;
    String? message;

    // Pattern 1: "saying X to Y" (e.g., "send message on WhatsApp saying hi to Yusuf")
    final match1 = RegExp(
      r'saying\s+(.+?)\s+to\s+(\w+)',
      caseSensitive: false,
    ).firstMatch(goal);

    // Pattern 2: "message X ... saying Y" (e.g., "message Yusuf on WhatsApp saying hi")
    final match2 = RegExp(
      r'message\s+(\w+).*?saying\s+(.+?)(?:\.|$)',
      caseSensitive: false,
    ).firstMatch(goal);

    // Pattern 3: "to X saying Y" (e.g., "send to Yusuf saying hello")
    final match3 = RegExp(
      r'to\s+(\w+)\s+saying\s+(.+?)(?:\.|$)',
      caseSensitive: false,
    ).firstMatch(goal);

    // Pattern 4: "whatsapp X saying Y"
    final match4 = RegExp(
      r'whatsapp\s+(\w+)\s+saying\s+(.+?)(?:\.|$)',
      caseSensitive: false,
    ).firstMatch(goal);

    // Pattern 5: Hindi pattern "X ko Y bhejo" (send Y to X)
    final match5 = RegExp(
      r'(\w+)\s+ko\s+(.+?)\s+(?:bhejo|bhej|send)',
      caseSensitive: false,
    ).firstMatch(goal);

    // Pattern 6: "send X to Y on whatsapp"
    final match6 = RegExp(
      r'send\s+(.+?)\s+to\s+(\w+)\s+on\s+whatsapp',
      caseSensitive: false,
    ).firstMatch(goal);

    if (match1 != null) {
      message = match1.group(1)?.trim();
      contact = match1.group(2)?.trim();
    } else if (match2 != null) {
      contact = match2.group(1)?.trim();
      message = match2.group(2)?.trim();
    } else if (match3 != null) {
      contact = match3.group(1)?.trim();
      message = match3.group(2)?.trim();
    } else if (match4 != null) {
      contact = match4.group(1)?.trim();
      message = match4.group(2)?.trim();
    } else if (match5 != null) {
      contact = match5.group(1)?.trim();
      message = match5.group(2)?.trim();
    } else if (match6 != null) {
      message = match6.group(1)?.trim();
      contact = match6.group(2)?.trim();
    }

    // Clean up
    if (contact != null && message != null) {
      // Capitalize contact name
      contact = contact[0].toUpperCase() + contact.substring(1).toLowerCase();
      // Remove trailing punctuation from message
      message = message.replaceAll(RegExp(r'[.\s]+$'), '');

      debugPrint(
        'HardcodedFlow: Parsed WhatsApp - Contact: $contact, Message: $message',
      );
      return {'contact': contact, 'message': message};
    }

    return null;
  }

  /// Execute a swipe gesture
  static Future<bool> _swipe(int x1, int y1, int x2, int y2) async {
    try {
      await _channel.invokeMethod('executeGesture', {
        'params': {'action': 'swipe', 'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2},
      });
      return true;
    } catch (e) {
      debugPrint('HardcodedFlow: swipe error: $e');
      return false;
    }
  }

  /// Book a Rapido cab using hardcoded coordinates.
  /// Coordinates calibrated for 1080x2400 screen.
  ///
  /// Flow:
  /// 1. Tap "Where are you going?" (540, 310)
  /// 2. Tap drop field (540, 470)
  /// 3. Type destination
  /// 4. Tap first result (540, 780)
  /// 5. Swipe up to reveal Sedan (540,1900 → 540,1100)
  /// 6. Tap Cab Sedan (540, 1650)
  /// 7. Tap Confirm Pickup (540, 2260)
  /// 8. Wait for screen transition
  /// 9. Tap Book Cab Sedan (540, 2220)
  static Future<bool> bookRapidoCab({
    required String destination,
    StepCallback? onStep,
  }) async {
    try {
      debugPrint(
        'HardcodedFlow: Starting Rapido cab booking - Destination: $destination',
      );

      // Pill is positioned on right side (x=900+) so it won't block center taps (x=540)
      // No need to hide overlay

      // Step 1: Tap "Where are you going?" to open destination search
      onStep?.call(1, 'Tapping destination field...');
      await _tap(540, 310);
      await _wait(1200); // Wait for search screen to open

      // Step 2: Tap the search/drop location input field to focus it
      onStep?.call(2, 'Focusing search field...');
      await _tap(540, 470);
      await _wait(800); // Wait for keyboard to appear

      // Step 3: Type destination
      onStep?.call(3, 'Typing $destination...');
      await _type(destination);
      await _wait(2500); // Wait longer for search results to load

      // Step 4: Tap first search result
      onStep?.call(4, 'Selecting $destination...');
      await _tap(540, 780);
      await _wait(2000); // Wait longer for ride options to load

      // Step 5: Swipe up to reveal ride options
      onStep?.call(5, 'Showing ride options...');
      await _swipe(540, 1900, 540, 1100);
      await _wait(1500);

      // Step 6: Tap Premium option
      onStep?.call(6, 'Selecting Premium...');
      await _tap(540, 1550);
      await _wait(1500);

      // Step 7: Tap first "Book Cab" button (after selecting Premium)
      onStep?.call(7, 'Booking cab...');
      await _tap(540, 2200);
      await _wait(2500); // Wait for next screen

      // Step 8: Tap "Confirm Pickup" button (same coordinates)
      onStep?.call(8, 'Confirming pickup location...');
      await _tap(540, 2200);
      await _wait(2500); // Wait for final screen

      // Step 9: Tap final "Book Cab" button (same coordinates)
      onStep?.call(9, 'Confirming booking...');
      await _tap(540, 2200);
      await _wait(1500);

      debugPrint('HardcodedFlow: Rapido cab booked successfully!');
      return true;
    } catch (e) {
      debugPrint('HardcodedFlow: bookRapidoCab error: $e');
      return false;
    }
  }

  /// Check if a goal matches Rapido booking pattern.
  /// Returns parsed {destination} or null if not a match.
  static Map<String, String>? parseRapidoGoal(String goal) {
    final goalLower = goal.toLowerCase();

    // Check if this is a Rapido request
    if (!goalLower.contains('rapido')) {
      return null;
    }

    String? destination;

    // Pattern 1: "book rapido to X"
    final match1 = RegExp(
      r'book\s+(?:a\s+)?rapido\s+to\s+(.+?)(?:\.|$)',
      caseSensitive: false,
    ).firstMatch(goal);

    // Pattern 2: "rapido to X"
    final match2 = RegExp(
      r'rapido\s+to\s+(.+?)(?:\.|$)',
      caseSensitive: false,
    ).firstMatch(goal);

    // Pattern 3: "go to X on/using/via rapido"
    final match3 = RegExp(
      r'go\s+to\s+(.+?)\s+(?:on|using|via|by)\s+rapido',
      caseSensitive: false,
    ).firstMatch(goal);

    // Pattern 4: Hindi - "rapido se X jana hai" or "X tak rapido"
    final match4 = RegExp(
      r'rapido\s+(?:se|par)\s+(.+?)\s+(?:jana|jao|chalo)',
      caseSensitive: false,
    ).firstMatch(goal);

    // Pattern 5: "X rapido" or "rapido X" where X is destination
    final match5 = RegExp(
      r'rapido\s+(?:book\s+)?(?:to\s+)?(.+?)(?:\.|$)',
      caseSensitive: false,
    ).firstMatch(goal);

    if (match1 != null) {
      destination = match1.group(1)?.trim();
    } else if (match2 != null) {
      destination = match2.group(1)?.trim();
    } else if (match3 != null) {
      destination = match3.group(1)?.trim();
    } else if (match4 != null) {
      destination = match4.group(1)?.trim();
    } else if (match5 != null) {
      destination = match5.group(1)?.trim();
    }

    // Clean up destination
    if (destination != null && destination.isNotEmpty) {
      // Remove common words that shouldn't be in destination
      destination = destination.replaceAll(
        RegExp(
          r'\s*(please|now|quickly|fast|asap|book|cab|taxi)\s*',
          caseSensitive: false,
        ),
        '',
      );
      destination = destination.trim();

      // Capitalize properly
      if (destination.isNotEmpty) {
        destination = destination
            .split(' ')
            .map((word) {
              if (word.isEmpty) return word;
              return word[0].toUpperCase() + word.substring(1).toLowerCase();
            })
            .join(' ');

        debugPrint('HardcodedFlow: Parsed Rapido - Destination: $destination');
        return {'destination': destination};
      }
    }

    return null;
  }

  /// Open PM Kisan website.
  static Future<bool> checkPmKisan() async {
    try {
      final result = await _channel.invokeMethod('checkPmKisan', {});
      return result == true;
    } catch (e) {
      debugPrint('HardcodedFlow: checkPmKisan error: $e');
      return false;
    }
  }
}
