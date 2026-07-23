import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SidebarHeader extends StatelessWidget {
  const SidebarHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: const Color(0xFF1E3354),
            ),
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Dashboard',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
