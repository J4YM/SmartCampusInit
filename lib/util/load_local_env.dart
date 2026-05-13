import 'load_local_env_io.dart' if (dart.library.html) 'load_local_env_web.dart'
    as impl;

Future<void> loadLocalEnv() => impl.loadLocalEnv();
