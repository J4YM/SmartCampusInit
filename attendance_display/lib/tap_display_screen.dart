import 'dart:async';

import 'package:flutter/material.dart';

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
        child: data == null ? _buildIdle() : _buildWelcome(data),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 90,
          backgroundColor: Colors.white24,
          backgroundImage: data.photoSignedUrl == null
              ? null
              : NetworkImage(data.photoSignedUrl!),
          child: data.photoSignedUrl == null
              ? const Icon(Icons.person, size: 90, color: Colors.white70)
              : null,
        ),
        const SizedBox(height: 24),
        Text(
          data.direction == 'in' ? 'Welcome!' : 'See you later!',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          data.name,
          style: const TextStyle(color: Colors.white, fontSize: 26),
        ),
        const SizedBox(height: 6),
        Text(
          data.section,
          style: const TextStyle(color: Colors.white60, fontSize: 18),
        ),
      ],
    );
  }
}
