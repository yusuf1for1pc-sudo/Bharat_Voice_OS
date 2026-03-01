import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/app_state_provider.dart';
import '../widgets/sparkle_icon.dart';
import '../widgets/animated_dotted_ring.dart';
import '../models/app_state.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0; // 0=welcome, 1=mic, 2=overlay, 3=accessibility

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    if (_step == 0) {
      return _buildWelcome(screenHeight);
    } else {
      return _buildPermissionStep();
    }
  }

  Widget _buildWelcome(double screenHeight) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Ring area
          SizedBox(
            height: screenHeight * 0.55,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const AnimatedDottedRing(state: RingState.idle),
                Text(
                  'SPEAK TO BEGIN',
                  style: TextStyle(
                    fontFamily: 'SpaceMono',
                    fontSize: 14,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const SparkleIcon(size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Get started',
                    style: GoogleFonts.inter(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Control your phone using your voice.',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: const Color(0xFF999999),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1A1A1A),
                          border: Border.all(
                            color: const Color(0xFF2A2A2A),
                          ),
                        ),
                        child: const Center(
                          child: SparkleIcon(size: 22),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _step = 1),
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Center(
                              child: Text(
                                'Get started',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
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
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionStep() {
    String title;
    String subtitle;
    String subtitleHindi;
    IconData icon;
    VoidCallback onGrant;

    switch (_step) {
      case 1:
        title = 'Microphone Access';
        subtitle = 'We need your microphone to listen to your voice commands.';
        subtitleHindi = 'आपकी आवाज़ सुनने के लिए माइक्रोफ़ोन चाहिए।';
        icon = Icons.mic;
        onGrant = _requestMicrophone;
        break;
      case 2:
        title = 'Display Over Apps';
        subtitle = 'Show a floating bubble over other apps for quick access.';
        subtitleHindi = 'अन्य ऐप्स के ऊपर फ़्लोटिंग बटन दिखाने के लिए।';
        icon = Icons.picture_in_picture;
        onGrant = _requestOverlay;
        break;
      case 3:
        title = 'Accessibility Service';
        subtitle = 'Control other apps on your behalf to complete tasks.';
        subtitleHindi = 'आपके काम पूरे करने के लिए अन्य ऐप्स को कंट्रोल करे।';
        icon = Icons.accessibility_new;
        onGrant = _requestAccessibility;
        break;
      default:
        return const SizedBox();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1A1A1A),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Icon(icon, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 32),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: const Color(0xFF999999),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitleHindi,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF666666),
                  height: 1.5,
                ),
              ),
              const Spacer(),
              // Step indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final isActive = i + 1 == _step;
                  return Container(
                    width: isActive ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.white : const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: onGrant,
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Center(
                    child: Text(
                      'Allow / अनुमति दें',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _skipToNext(),
                child: Text(
                  'Skip for now',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF999999),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestMicrophone() async {
    await Permission.microphone.request();
    _skipToNext();
  }

  Future<void> _requestOverlay() async {
    // Overlay permission requires navigating to settings on Android
    // For now, skip to next
    _skipToNext();
  }

  Future<void> _requestAccessibility() async {
    // Accessibility requires navigating to settings
    // For now, complete onboarding
    await _completeOnboarding();
  }

  void _skipToNext() {
    if (_step < 3) {
      setState(() => _step++);
    } else {
      _completeOnboarding();
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (!mounted) return;
    context.read<AppStateProvider>().setOnboardingComplete(true);
  }
}
