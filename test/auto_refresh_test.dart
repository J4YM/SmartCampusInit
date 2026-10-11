import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/app/auto_refresh.dart';

class _Probe extends StatefulWidget {
  const _Probe({required this.refresh, this.interval = const Duration(seconds: 10)});

  final Future<void> Function() refresh;
  final Duration interval;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with AutoRefreshMixin {
  @override
  void initState() {
    super.initState();
    startAutoRefresh(widget.refresh, interval: widget.interval);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets('refreshes on every interval', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_Probe(refresh: () async => calls++));
    expect(calls, 0);

    await tester.pump(const Duration(seconds: 10));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 3);
  });

  testWidgets('never overlaps: a slow refresh is waited out', (tester) async {
    var started = 0;
    final gate = Completer<void>();
    await tester.pumpWidget(_Probe(refresh: () {
      started++;
      return gate.future;
    }));

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(started, 1, reason: 'later ticks skip while one is in flight');

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(started, 2);
  });

  testWidgets('a refresh that hangs forever does not stall later ones',
      (tester) async {
    var started = 0;
    await tester.pumpWidget(_Probe(refresh: () {
      started++;
      return Completer<void>().future; // never completes
    }));

    await tester.pump(const Duration(seconds: 10));
    expect(started, 1);
    // Abandoned after the timeout, so the next tick starts a fresh pass.
    await tester.pump(kAutoRefreshTimeout + const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(started, greaterThan(1));
    expect(tester.takeException(), isNull);

    // Let the last pass's timeout lapse so no timer outlives the test.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(kAutoRefreshTimeout);
  });

  testWidgets('a failing refresh is survived and retried', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_Probe(refresh: () async {
      calls++;
      if (calls == 1) throw StateError('offline');
    }));

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stops when the page goes away', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_Probe(refresh: () async => calls++));
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 1);
  });

  testWidgets('rests while the app is hidden and catches up on resume',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_Probe(refresh: () async => calls++));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 0, reason: 'nothing while backgrounded');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 1, reason: 'refreshes straight away on return');
  });
}
