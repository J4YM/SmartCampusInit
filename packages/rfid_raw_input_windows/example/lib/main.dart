import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rfid_raw_input_windows/rfid_raw_input_windows.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Replace with the target reader's actual vendor/product id — read
  // these off Windows Device Manager -> reader device -> Properties ->
  // Details -> Hardware Ids (format VID_xxxx&PID_xxxx).
  static const _vendorId = 0x0000;
  static const _productId = 0x0000;

  String _status = 'Checking for device...';
  StreamSubscription<String>? _subscription;
  final _taps = <String>[];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final found = await RfidRawInputReader.deviceFound(_vendorId, _productId);
    if (!mounted) return;
    setState(() {
      _status = found ? 'Device found — listening for taps' : 'Device not found';
    });
    _subscription = RfidRawInputReader.taps(_vendorId, _productId).listen((uid) {
      if (!mounted) return;
      setState(() => _taps.insert(0, uid));
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Plugin example app')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_status),
            ),
            Expanded(
              child: ListView(
                children: _taps.map((uid) => ListTile(title: Text(uid))).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
