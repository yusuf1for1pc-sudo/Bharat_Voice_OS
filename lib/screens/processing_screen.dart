import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../models/app_state.dart';
import '../widgets/animated_dotted_ring.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  final List<String> _narrationLines = [
    'समझ रहा हूँ...',
    'Ola खोल रहा हूँ...',
    'Destination डाल रहा हूँ...',
  ];
  int _currentLine = 0;

  @override
  void initState() {
    super.initState();
    _animateNarration();
  }

  void _animateNarration() async {
    for (int i = 0; i < _narrationLines.length; i++) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      setState(() => _currentLine = i);
    }
    // After narration, simulate receiving result
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    // Mock: navigate to agent result
    final appState = context.read<AppStateProvider>();
    appState.setResult(TaskResult(
      mode: 'agent',
      title: 'Cab Booked',
      details: [
        TaskDetail(icon: 'car', text: 'Ola Auto · Marine Drive'),
        TaskDetail(icon: 'clock', text: 'Ramesh · 12 min away'),
        TaskDetail(icon: 'rupee', text: 'Est. ₹85'),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Blob ring (70% height)
          SizedBox(
            height: screenHeight * 0.65,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedDottedRing(
                  state: RingState.processing,
                ),
                // "Processing..." text
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Processing...',
                      style: TextStyle(
                        fontFamily: 'SpaceMono',
                        fontSize: 14,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 16,
                      margin: const EdgeInsets.only(left: 2),
                      color: Colors.white,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Narration text
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  for (int i = 0; i <= _currentLine && i < _narrationLines.length; i++)
                    AnimatedOpacity(
                      opacity: i == _currentLine ? 1.0 : (i == _currentLine - 1 ? 0.5 : 0.2),
                      duration: const Duration(milliseconds: 500),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _narrationLines[i],
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            color: i == _currentLine
                                ? Colors.white
                                : const Color(0xFF999999),
                            fontWeight: i == _currentLine
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
