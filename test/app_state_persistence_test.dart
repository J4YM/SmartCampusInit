import 'package:capstone_dashboard/app/app_state_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStatePersistence.resetForTesting();
  });

  test('demoUsername is null until set, then persists and can be cleared',
      () async {
    final persistence = await AppStatePersistence.instance();
    expect(persistence.demoUsername, isNull);

    await persistence.setDemoUsername('registrar.demo');
    expect(persistence.demoUsername, 'registrar.demo');

    await persistence.setDemoUsername(null);
    expect(persistence.demoUsername, isNull);
  });

  test('navState keeps each key\'s value independent of every other key',
      () async {
    final persistence = await AppStatePersistence.instance();

    await persistence.setNavState('adminModule', 'registrar');
    await persistence.setNavState('registrarTab', 'grades');

    expect(persistence.navState('adminModule'), 'registrar');
    expect(persistence.navState('registrarTab'), 'grades');
    expect(persistence.navState('somethingNeverSet'), isNull);
  });

  test('clearAllNavState removes every nav slot but leaves demoUsername '
      'untouched', () async {
    final persistence = await AppStatePersistence.instance();
    await persistence.setDemoUsername('do.demo');
    await persistence.setNavState('adminModule', 'registrar');
    await persistence.setNavState('registrarTab', 'grades');

    await persistence.clearAllNavState();

    expect(persistence.navState('adminModule'), isNull);
    expect(persistence.navState('registrarTab'), isNull);
    expect(persistence.demoUsername, 'do.demo');
  });
}
