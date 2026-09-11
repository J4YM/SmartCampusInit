import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

void main() {
  test('IdCardTemplateElement round-trips a text element through JSON', () {
    const element = IdCardTemplateElement(
      id: 'el-1',
      type: IdCardElementType.staticText,
      x: 10,
      y: 12,
      width: 80,
      height: 20,
      zIndex: 2,
      textContent: 'STI Baliuag',
      fontFamily: 'Poppins',
      fontSize: 10,
      color: 0xFF000000,
      textAlign: 'left',
    );

    final restored = IdCardTemplateElement.fromJson(element.toJson());

    expect(restored.id, 'el-1');
    expect(restored.type, IdCardElementType.staticText);
    expect(restored.x, 10);
    expect(restored.y, 12);
    expect(restored.width, 80);
    expect(restored.height, 20);
    expect(restored.zIndex, 2);
    expect(restored.textContent, 'STI Baliuag');
    expect(restored.fontFamily, 'Poppins');
    expect(restored.fontSize, 10);
    expect(restored.color, 0xFF000000);
    expect(restored.textAlign, 'left');
  });

  test('IdCardTemplateElement round-trips an idData element through JSON', () {
    const element = IdCardTemplateElement(
      id: 'el-2',
      type: IdCardElementType.idData,
      x: 0,
      y: 0,
      width: 50,
      height: 15,
      fieldKey: IdDataFieldKey.guardianContactNo,
    );

    final restored = IdCardTemplateElement.fromJson(element.toJson());

    expect(restored.type, IdCardElementType.idData);
    expect(restored.fieldKey, IdDataFieldKey.guardianContactNo);
  });

  test('IdCardTemplateElement round-trips a roundedRect element through JSON',
      () {
    const element = IdCardTemplateElement(
      id: 'el-3',
      type: IdCardElementType.roundedRect,
      x: 0,
      y: 0,
      width: 40,
      height: 40,
      fillColor: 0x00000000,
      strokeColor: 0xFF345892,
      strokeWidth: 1.5,
      cornerRadius: 8,
    );

    final restored = IdCardTemplateElement.fromJson(element.toJson());

    expect(restored.type, IdCardElementType.roundedRect);
    expect(restored.fillColor, 0x00000000);
    expect(restored.strokeColor, 0xFF345892);
    expect(restored.strokeWidth, 1.5);
    expect(restored.cornerRadius, 8);
  });
}
