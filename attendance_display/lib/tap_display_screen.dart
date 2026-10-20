import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kiosk/kiosk_module.dart' show AttendanceWelcomeCard;

import 'tap_display_data.dart';

class TapDisplayScreen extends StatefulWidget {
  const TapDisplayScreen({super.key, required this.tapStream});

  final Stream<TapDisplayData> tapStream;

  @override
  State<TapDisplayScreen> createState() => _TapDisplayScreenState();
}

class _TapDisplayScreenState extends State<TapDisplayScreen> {
  static const _showDuration = Duration(seconds: 5);

  StreamSubscription<TapDisplayData>? _subscription;
  TapDisplayData? _current;
  Timer? _revertTimer;

  @override
  void initState() {
    super.initState();
    _subscription = widget.tapStream.listen(_handleTap);
  }

  void _handleTap(TapDisplayData data) {
    _revertTimer?.cancel();
    setState(() => _current = data);
    _revertTimer = Timer(_showDuration, () {
      if (mounted) setState(() => _current = null);
    });
  }

  @override
  void dispose() {
    _revertTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _current;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: data == null
            ? _buildIdle()
            : (data.recognized ? _buildWelcome(data) : _buildNotRecognized(data)),
      ),
    );
  }

  /// A card that belongs to no student: big, red and unmistakable, so the
  /// person tapping (and anyone watching) knows the tap was not recorded.
  Widget _buildNotRecognized(TapDisplayData data) {
    final at = data.tappedAt;
    return Container(
      key: const Key('card-not-recognized'),
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
      decoration: BoxDecoration(
        color: const Color(0xFFB91C1C),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white, size: 96),
          const SizedBox(height: 16),
          const Text(
            'Card not recognized',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your attendance was not recorded. Please see the registrar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 26),
          ),
          if (at != null) ...[
            const SizedBox(height: 16),
            Text(
              formatTapDateTime(at),
              style: const TextStyle(color: Colors.white70, fontSize: 22),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIdle() {
    return const Text(
      'Tap your ID to check in',
      style: TextStyle(color: Colors.white70, fontSize: 28),
    );
  }

  Widget _buildWelcome(TapDisplayData data) {
    final photoUrl = data.photoSignedUrl;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: AttendanceWelcomeCard(
        title: data.direction == 'in' ? 'Welcome, STIer!' : 'See you later, STIer!',
        name: data.name,
        courseSection: data.section,
        photo: photoUrl == null ? null : NetworkImage(photoUrl),
        tappedAt: data.tappedAt,
      ),
    );
  }
}
