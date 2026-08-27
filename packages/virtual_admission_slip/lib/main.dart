import 'package:flutter/material.dart';

import 'admission_slip_data.dart';
import 'admission_slip_generated_view.dart';

void main() {
  runApp(const VirtualAdmissionSlipApp());
}

class VirtualAdmissionSlipApp extends StatelessWidget {
  const VirtualAdmissionSlipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Virtual Admission Slip',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFE6F7F1),
      ),
      home: AdmissionSlipPreviewScreen(
        data: const AdmissionSlipData(
          qrUrl: 'https://example.com/slip/demo-slip-id',
        ),
        onPrint: () async {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        },
        onDone: () {},
      ),
    );
  }
}
