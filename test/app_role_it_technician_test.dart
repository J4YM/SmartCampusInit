import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/auth/app_role.dart';
import 'package:capstone_dashboard/modules/module_access.dart';
import 'package:capstone_dashboard/modules/system_module_id.dart';

void main() {
  test('IT Technician role round-trips through the db-value mapping', () {
    expect(appRoleToDbValue(AppRole.itTechnician), 'IT_Technician');
    expect(appRoleFromDbValue('IT_Technician'), AppRole.itTechnician);
  });

  test('IT Technician can see the module; existing roles keep access', () {
    expect(
      ModuleAccess.canSeeModule(AppRole.itTechnician, SystemModuleId.rfidManagement),
      isTrue,
    );
    expect(
      ModuleAccess.canSeeModule(AppRole.administrator, SystemModuleId.rfidManagement),
      isTrue,
    );
    expect(
      ModuleAccess.canSeeModule(AppRole.registrar, SystemModuleId.rfidManagement),
      isTrue,
    );
    expect(
      ModuleAccess.canSeeModule(AppRole.securityPersonnel, SystemModuleId.rfidManagement),
      isTrue,
    );
    expect(
      ModuleAccess.canSeeModule(AppRole.teacher, SystemModuleId.rfidManagement),
      isFalse,
    );
  });

  test('The module title reflects the new dashboard name', () {
    expect(SystemModuleId.rfidManagement.title, 'IT Technician Dashboard');
  });
}
