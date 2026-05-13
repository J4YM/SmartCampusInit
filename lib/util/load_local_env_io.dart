import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> loadLocalEnv() async {
  final file = File('.env');
  if (await file.exists()) {
    dotenv.testLoad(fileInput: await file.readAsString());
  } else {
    dotenv.testLoad(fileInput: '');
  }
}
