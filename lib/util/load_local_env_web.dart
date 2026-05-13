import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> loadLocalEnv() async {
  await dotenv.load(fileName: '.env', isOptional: true);
}
