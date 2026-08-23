import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/admission_slip_repository.dart';
import '../env.dart';

/// What a phone camera opens when it scans the QR on a printed/on-screen
/// admission slip — a read-only view of everything filed under one slip
/// id. Deliberately minimal (no login, no actions) — the "teacher scans to
/// validate attendance" follow-up is out of scope for this pass (see
/// `supabase/add_admission_slips_schema.sql`'s `redeemed_at`/`redeemed_by`
/// columns, reserved for it).
class SlipLookupPage extends StatefulWidget {
  const SlipLookupPage({super.key, required this.slipId});

  /// Parsed from the URL path by `main_slip.dart` — null when the link is
  /// malformed (no id segment at all).
  final String? slipId;

  @override
  State<SlipLookupPage> createState() => _SlipLookupPageState();
}

class _SlipLookupPageState extends State<SlipLookupPage> {
  bool _loading = true;
  String? _error;
  AdmissionSlipDetail? _detail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final slipId = widget.slipId;
    if (slipId == null || slipId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This link is missing a slip id.';
      });
      return;
    }
    if (!AppEnv.supabaseConfigured) {
      setState(() {
        _loading = false;
        _error = 'This page is not configured.';
      });
      return;
    }
    try {
      final repo = AdmissionSlipRepository(Supabase.instance.client);
      final detail = await repo.fetchSlipDetail(slipId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _detail = detail;
        if (detail == null) {
          _error = 'No admission slip found for this link. It may have '
              'expired or the link may be incorrect.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this slip: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _loading
                  ? const CircularProgressIndicator()
                  : _error != null
                      ? _ErrorCard(message: _error!)
                      : _SlipDetailCard(detail: _detail!),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Color(0xFFDC2626)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _SlipDetailCard extends StatelessWidget {
  const _SlipDetailCard({required this.detail});

  final AdmissionSlipDetail detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'VIRTUAL ADMISSION SLIP',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Disciplinary Office',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            _field('Student', detail.studentName),
            _field('Student Number', detail.studentNumber),
            _field('Grade & Section', detail.gradeSection),
            _field('Filed By', detail.reportedByName),
            _field('Date & Time', detail.createdAt.toLocal().toString()),
            const SizedBox(height: 16),
            const Text('Acknowledged Violations',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            for (final v in detail.violations)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(v.offenseLabel)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          v.status,
                          style: const TextStyle(fontSize: 11, color: Colors.white),
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

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
