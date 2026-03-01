import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../models/app_state.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();

    // Demo data if no history yet
    final items = appState.history.isEmpty
        ? [
            HistoryItem(
              icon: '🚕',
              title: 'Cab booked',
              subtitle: 'Your Ola to Marine Drive is on its way.',
              time: '10:30 AM',
            ),
            HistoryItem(
              icon: '📋',
              title: 'PM Kisan checked',
              subtitle: 'Status: Next installment pending.',
              time: '9:15 AM',
            ),
            HistoryItem(
              icon: '💬',
              title: 'Message sent',
              subtitle: 'Sent to Rahul: "Running 5 mins late."',
              time: '8:45 AM',
            ),
          ]
        : appState.history;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Header row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // Settings circle
                  _circleButton(Icons.settings),
                  const SizedBox(width: 12),
                  // Title
                  Expanded(
                    child: Text(
                      'Bharat Voice OS',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Search circle
                  _circleButton(Icons.search),
                  const SizedBox(width: 8),
                  // Arrow circle
                  GestureDetector(
                    onTap: () => appState.goHome(),
                    child: _circleButton(Icons.arrow_forward),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Task cards list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _taskCard(item);
                },
              ),
            ),

            // Bottom toggle: Threads / Spaces
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: const Color(0xFF2A2A2A),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Threads — selected
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Center(
                          child: Text(
                            'Threads',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Spaces — unselected
                    Expanded(
                      child: Center(
                        child: Text(
                          'Spaces',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            color: const Color(0xFF999999),
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
      ),
    );
  }

  Widget _circleButton(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1A1A1A),
        border: Border.all(
          color: const Color(0xFF2A2A2A),
          width: 1,
        ),
      ),
      child: Icon(icon, color: const Color(0xFF999999), size: 20),
    );
  }

  Widget _taskCard(HistoryItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF2A2A2A),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(item.icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Text(
                item.title,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.subtitle,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF999999),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.time,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }
}
