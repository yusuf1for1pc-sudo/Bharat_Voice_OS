import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../models/app_state.dart';
import '../widgets/animated_dotted_ring.dart';

class ListeningScreen extends StatelessWidget {
  const ListeningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Top: Dotted ring (covers upper portion)
          SizedBox(
            height: screenHeight * 0.48,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedDottedRing(
                  state: RingState.listening,
                  audioAmplitudes: null,
                ),
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

          // Bottom sheet - frosted glass
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: screenHeight * 0.55,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.08),
                        Colors.white.withValues(alpha: 0.15),
                        Colors.white.withValues(alpha: 0.22),
                      ],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),

                      // Pill bar with X, "Listening...", gear
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 8),
                              // X button
                              GestureDetector(
                                onTap: () => appState.goHome(),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(alpha: 0.12),
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              // "Listening..."
                              Text(
                                'Listening...',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  color: Colors.white70,
                                ),
                              ),
                              const Spacer(),
                              // Gear icon
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                                child: const Icon(
                                  Icons.settings,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Live transcript
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Center(
                            child: Text(
                              appState.transcript.isEmpty
                                  ? 'Ola se cab book karo\nMarine Drive ke liye'
                                  : appState.transcript,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Audio waveform icon at bottom
                      Padding(
                        padding: const EdgeInsets.only(bottom: 40),
                        child: Icon(
                          Icons.graphic_eq,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
