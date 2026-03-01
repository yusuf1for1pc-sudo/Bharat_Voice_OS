import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';

import '../widgets/animated_dotted_ring.dart';
import '../widgets/sparkle_icon.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _cursorVisible = true;

  @override
  void initState() {
    super.initState();
    // Blinking cursor
    _startCursorBlink();
  }

  void _startCursorBlink() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return false;
      setState(() => _cursorVisible = !_cursorVisible);
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Top section: Dotted Ring (55% of screen)
          SizedBox(
            height: screenHeight * 0.58,
            child: GestureDetector(
              onTap: () => appState.startListening(),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // The ring
                  AnimatedDottedRing(
                    state: appState.ringState,
                  ),
                  // "SPEAK TO BEGIN" text with blinking cursor
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'SPEAK TO BEGIN',
                        style: TextStyle(
                          fontFamily: 'SpaceMono',
                          fontSize: 14,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                      AnimatedOpacity(
                        opacity: _cursorVisible ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 100),
                        child: Container(
                          width: 8,
                          height: 16,
                          margin: const EdgeInsets.only(left: 2),
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bottom section
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Sparkle icon
                  const SparkleIcon(size: 48, color: Colors.white),
                  const SizedBox(height: 16),

                  // "Get started" heading
                  Text(
                    'Get started',
                    style: GoogleFonts.inter(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    'Control your phone using your voice.',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: const Color(0xFF999999),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Bottom row: circle button + Get started pill
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Dark circle button with sparkle
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1A1A1A),
                          border: Border.all(
                            color: const Color(0xFF2A2A2A),
                            width: 1,
                          ),
                        ),
                        child: const Center(
                          child: SparkleIcon(size: 22, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // White pill "Get started" button
                      Expanded(
                        child: GestureDetector(
                          onTap: () => appState.startListening(),
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
}
