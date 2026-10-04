// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kiosk_database.dart';

// ignore_for_file: type=lint
class $CachedStudentsTable extends CachedStudents
    with TableInfo<$CachedStudentsTable, CachedStudentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedStudentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _rfidUidMeta =
      const VerificationMeta('rfidUid');
  @override
  late final GeneratedColumn<String> rfidUid = GeneratedColumn<String>(
      'rfid_uid', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fullNameMeta =
      const VerificationMeta('fullName');
  @override
  late final GeneratedColumn<String> fullName = GeneratedColumn<String>(
      'full_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _studentNumberMeta =
      const VerificationMeta('studentNumber');
  @override
  late final GeneratedColumn<String> studentNumber = GeneratedColumn<String>(
      'student_number', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _gradeSectionMeta =
      const VerificationMeta('gradeSection');
  @override
  late final GeneratedColumn<String> gradeSection = GeneratedColumn<String>(
      'grade_section', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _courseMeta = const VerificationMeta('course');
  @override
  late final GeneratedColumn<String> course = GeneratedColumn<String>(
      'course', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, rfidUid, fullName, studentNumber, gradeSection, course];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_students';
  @override
  VerificationContext validateIntegrity(Insertable<CachedStudentRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('rfid_uid')) {
      context.handle(_rfidUidMeta,
          rfidUid.isAcceptableOrUnknown(data['rfid_uid']!, _rfidUidMeta));
    } else if (isInserting) {
      context.missing(_rfidUidMeta);
    }
    if (data.containsKey('full_name')) {
      context.handle(_fullNameMeta,
          fullName.isAcceptableOrUnknown(data['full_name']!, _fullNameMeta));
    } else if (isInserting) {
      context.missing(_fullNameMeta);
    }
    if (data.containsKey('student_number')) {
      context.handle(
          _studentNumberMeta,
          studentNumber.isAcceptableOrUnknown(
              data['student_number']!, _studentNumberMeta));
    } else if (isInserting) {
      context.missing(_studentNumberMeta);
    }
    if (data.containsKey('grade_section')) {
      context.handle(
          _gradeSectionMeta,
          gradeSection.isAcceptableOrUnknown(
              data['grade_section']!, _gradeSectionMeta));
    } else if (isInserting) {
      context.missing(_gradeSectionMeta);
    }
    if (data.containsKey('course')) {
      context.handle(_courseMeta,
          course.isAcceptableOrUnknown(data['course']!, _courseMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedStudentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedStudentRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      rfidUid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rfid_uid'])!,
      fullName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}full_name'])!,
      studentNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}student_number'])!,
      gradeSection: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}grade_section'])!,
      course: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}course']),
    );
  }

  @override
  $CachedStudentsTable createAlias(String alias) {
    return $CachedStudentsTable(attachedDatabase, alias);
  }
}

class CachedStudentRow extends DataClass
    implements Insertable<CachedStudentRow> {
  final String id;
  final String rfidUid;
  final String fullName;
  final String studentNumber;
  final String gradeSection;
  final String? course;
  const CachedStudentRow(
      {required this.id,
      required this.rfidUid,
      required this.fullName,
      required this.studentNumber,
      required this.gradeSection,
      this.course});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['rfid_uid'] = Variable<String>(rfidUid);
    map['full_name'] = Variable<String>(fullName);
    map['student_number'] = Variable<String>(studentNumber);
    map['grade_section'] = Variable<String>(gradeSection);
    if (!nullToAbsent || course != null) {
      map['course'] = Variable<String>(course);
    }
    return map;
  }

  CachedStudentsCompanion toCompanion(bool nullToAbsent) {
    return CachedStudentsCompanion(
      id: Value(id),
      rfidUid: Value(rfidUid),
      fullName: Value(fullName),
      studentNumber: Value(studentNumber),
      gradeSection: Value(gradeSection),
      course:
          course == null && nullToAbsent ? const Value.absent() : Value(course),
    );
  }

  factory CachedStudentRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedStudentRow(
      id: serializer.fromJson<String>(json['id']),
      rfidUid: serializer.fromJson<String>(json['rfidUid']),
      fullName: serializer.fromJson<String>(json['fullName']),
      studentNumber: serializer.fromJson<String>(json['studentNumber']),
      gradeSection: serializer.fromJson<String>(json['gradeSection']),
      course: serializer.fromJson<String?>(json['course']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'rfidUid': serializer.toJson<String>(rfidUid),
      'fullName': serializer.toJson<String>(fullName),
      'studentNumber': serializer.toJson<String>(studentNumber),
      'gradeSection': serializer.toJson<String>(gradeSection),
      'course': serializer.toJson<String?>(course),
    };
  }

  CachedStudentRow copyWith(
          {String? id,
          String? rfidUid,
          String? fullName,
          String? studentNumber,
          String? gradeSection,
          Value<String?> course = const Value.absent()}) =>
      CachedStudentRow(
        id: id ?? this.id,
        rfidUid: rfidUid ?? this.rfidUid,
        fullName: fullName ?? this.fullName,
        studentNumber: studentNumber ?? this.studentNumber,
        gradeSection: gradeSection ?? this.gradeSection,
        course: course.present ? course.value : this.course,
      );
  CachedStudentRow copyWithCompanion(CachedStudentsCompanion data) {
    return CachedStudentRow(
      id: data.id.present ? data.id.value : this.id,
      rfidUid: data.rfidUid.present ? data.rfidUid.value : this.rfidUid,
      fullName: data.fullName.present ? data.fullName.value : this.fullName,
      studentNumber: data.studentNumber.present
          ? data.studentNumber.value
          : this.studentNumber,
      gradeSection: data.gradeSection.present
          ? data.gradeSection.value
          : this.gradeSection,
      course: data.course.present ? data.course.value : this.course,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedStudentRow(')
          ..write('id: $id, ')
          ..write('rfidUid: $rfidUid, ')
          ..write('fullName: $fullName, ')
          ..write('studentNumber: $studentNumber, ')
          ..write('gradeSection: $gradeSection, ')
          ..write('course: $course')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, rfidUid, fullName, studentNumber, gradeSection, course);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedStudentRow &&
          other.id == this.id &&
          other.rfidUid == this.rfidUid &&
          other.fullName == this.fullName &&
          other.studentNumber == this.studentNumber &&
          other.gradeSection == this.gradeSection &&
          other.course == this.course);
}

class CachedStudentsCompanion extends UpdateCompanion<CachedStudentRow> {
  final Value<String> id;
  final Value<String> rfidUid;
  final Value<String> fullName;
  final Value<String> studentNumber;
  final Value<String> gradeSection;
  final Value<String?> course;
  final Value<int> rowid;
  const CachedStudentsCompanion({
    this.id = const Value.absent(),
    this.rfidUid = const Value.absent(),
    this.fullName = const Value.absent(),
    this.studentNumber = const Value.absent(),
    this.gradeSection = const Value.absent(),
    this.course = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedStudentsCompanion.insert({
    required String id,
    required String rfidUid,
    required String fullName,
    required String studentNumber,
    required String gradeSection,
    this.course = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        rfidUid = Value(rfidUid),
        fullName = Value(fullName),
        studentNumber = Value(studentNumber),
        gradeSection = Value(gradeSection);
  static Insertable<CachedStudentRow> custom({
    Expression<String>? id,
    Expression<String>? rfidUid,
    Expression<String>? fullName,
    Expression<String>? studentNumber,
    Expression<String>? gradeSection,
    Expression<String>? course,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rfidUid != null) 'rfid_uid': rfidUid,
      if (fullName != null) 'full_name': fullName,
      if (studentNumber != null) 'student_number': studentNumber,
      if (gradeSection != null) 'grade_section': gradeSection,
      if (course != null) 'course': course,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedStudentsCompanion copyWith(
      {Value<String>? id,
      Value<String>? rfidUid,
      Value<String>? fullName,
      Value<String>? studentNumber,
      Value<String>? gradeSection,
      Value<String?>? course,
      Value<int>? rowid}) {
    return CachedStudentsCompanion(
      id: id ?? this.id,
      rfidUid: rfidUid ?? this.rfidUid,
      fullName: fullName ?? this.fullName,
      studentNumber: studentNumber ?? this.studentNumber,
      gradeSection: gradeSection ?? this.gradeSection,
      course: course ?? this.course,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (rfidUid.present) {
      map['rfid_uid'] = Variable<String>(rfidUid.value);
    }
    if (fullName.present) {
      map['full_name'] = Variable<String>(fullName.value);
    }
    if (studentNumber.present) {
      map['student_number'] = Variable<String>(studentNumber.value);
    }
    if (gradeSection.present) {
      map['grade_section'] = Variable<String>(gradeSection.value);
    }
    if (course.present) {
      map['course'] = Variable<String>(course.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedStudentsCompanion(')
          ..write('id: $id, ')
          ..write('rfidUid: $rfidUid, ')
          ..write('fullName: $fullName, ')
          ..write('studentNumber: $studentNumber, ')
          ..write('gradeSection: $gradeSection, ')
          ..write('course: $course, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedStaffTable extends CachedStaff
    with TableInfo<$CachedStaffTable, CachedStaffRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedStaffTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _rfidCardIdMeta =
      const VerificationMeta('rfidCardId');
  @override
  late final GeneratedColumn<String> rfidCardId = GeneratedColumn<String>(
      'rfid_card_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fullNameMeta =
      const VerificationMeta('fullName');
  @override
  late final GeneratedColumn<String> fullName = GeneratedColumn<String>(
      'full_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, rfidCardId, fullName, role];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_staff';
  @override
  VerificationContext validateIntegrity(Insertable<CachedStaffRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('rfid_card_id')) {
      context.handle(
          _rfidCardIdMeta,
          rfidCardId.isAcceptableOrUnknown(
              data['rfid_card_id']!, _rfidCardIdMeta));
    } else if (isInserting) {
      context.missing(_rfidCardIdMeta);
    }
    if (data.containsKey('full_name')) {
      context.handle(_fullNameMeta,
          fullName.isAcceptableOrUnknown(data['full_name']!, _fullNameMeta));
    } else if (isInserting) {
      context.missing(_fullNameMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedStaffRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedStaffRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      rfidCardId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rfid_card_id'])!,
      fullName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}full_name'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
    );
  }

  @override
  $CachedStaffTable createAlias(String alias) {
    return $CachedStaffTable(attachedDatabase, alias);
  }
}

class CachedStaffRow extends DataClass implements Insertable<CachedStaffRow> {
  final String id;
  final String rfidCardId;
  final String fullName;
  final String role;
  const CachedStaffRow(
      {required this.id,
      required this.rfidCardId,
      required this.fullName,
      required this.role});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['rfid_card_id'] = Variable<String>(rfidCardId);
    map['full_name'] = Variable<String>(fullName);
    map['role'] = Variable<String>(role);
    return map;
  }

  CachedStaffCompanion toCompanion(bool nullToAbsent) {
    return CachedStaffCompanion(
      id: Value(id),
      rfidCardId: Value(rfidCardId),
      fullName: Value(fullName),
      role: Value(role),
    );
  }

  factory CachedStaffRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedStaffRow(
      id: serializer.fromJson<String>(json['id']),
      rfidCardId: serializer.fromJson<String>(json['rfidCardId']),
      fullName: serializer.fromJson<String>(json['fullName']),
      role: serializer.fromJson<String>(json['role']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'rfidCardId': serializer.toJson<String>(rfidCardId),
      'fullName': serializer.toJson<String>(fullName),
      'role': serializer.toJson<String>(role),
    };
  }

  CachedStaffRow copyWith(
          {String? id, String? rfidCardId, String? fullName, String? role}) =>
      CachedStaffRow(
        id: id ?? this.id,
        rfidCardId: rfidCardId ?? this.rfidCardId,
        fullName: fullName ?? this.fullName,
        role: role ?? this.role,
      );
  CachedStaffRow copyWithCompanion(CachedStaffCompanion data) {
    return CachedStaffRow(
      id: data.id.present ? data.id.value : this.id,
      rfidCardId:
          data.rfidCardId.present ? data.rfidCardId.value : this.rfidCardId,
      fullName: data.fullName.present ? data.fullName.value : this.fullName,
      role: data.role.present ? data.role.value : this.role,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedStaffRow(')
          ..write('id: $id, ')
          ..write('rfidCardId: $rfidCardId, ')
          ..write('fullName: $fullName, ')
          ..write('role: $role')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, rfidCardId, fullName, role);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedStaffRow &&
          other.id == this.id &&
          other.rfidCardId == this.rfidCardId &&
          other.fullName == this.fullName &&
          other.role == this.role);
}

class CachedStaffCompanion extends UpdateCompanion<CachedStaffRow> {
  final Value<String> id;
  final Value<String> rfidCardId;
  final Value<String> fullName;
  final Value<String> role;
  final Value<int> rowid;
  const CachedStaffCompanion({
    this.id = const Value.absent(),
    this.rfidCardId = const Value.absent(),
    this.fullName = const Value.absent(),
    this.role = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedStaffCompanion.insert({
    required String id,
    required String rfidCardId,
    required String fullName,
    required String role,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        rfidCardId = Value(rfidCardId),
        fullName = Value(fullName),
        role = Value(role);
  static Insertable<CachedStaffRow> custom({
    Expression<String>? id,
    Expression<String>? rfidCardId,
    Expression<String>? fullName,
    Expression<String>? role,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rfidCardId != null) 'rfid_card_id': rfidCardId,
      if (fullName != null) 'full_name': fullName,
      if (role != null) 'role': role,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedStaffCompanion copyWith(
      {Value<String>? id,
      Value<String>? rfidCardId,
      Value<String>? fullName,
      Value<String>? role,
      Value<int>? rowid}) {
    return CachedStaffCompanion(
      id: id ?? this.id,
      rfidCardId: rfidCardId ?? this.rfidCardId,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (rfidCardId.present) {
      map['rfid_card_id'] = Variable<String>(rfidCardId.value);
    }
    if (fullName.present) {
      map['full_name'] = Variable<String>(fullName.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedStaffCompanion(')
          ..write('id: $id, ')
          ..write('rfidCardId: $rfidCardId, ')
          ..write('fullName: $fullName, ')
          ..write('role: $role, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedOffensesTable extends CachedOffenses
    with TableInfo<$CachedOffensesTable, CachedOffenseRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedOffensesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
      'label', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [id, label, category];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_offenses';
  @override
  VerificationContext validateIntegrity(Insertable<CachedOffenseRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
          _labelMeta, label.isAcceptableOrUnknown(data['label']!, _labelMeta));
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedOffenseRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedOffenseRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      label: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}label'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category']),
    );
  }

  @override
  $CachedOffensesTable createAlias(String alias) {
    return $CachedOffensesTable(attachedDatabase, alias);
  }
}

class CachedOffenseRow extends DataClass
    implements Insertable<CachedOffenseRow> {
  final String id;
  final String label;
  final String? category;
  const CachedOffenseRow(
      {required this.id, required this.label, this.category});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['label'] = Variable<String>(label);
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    return map;
  }

  CachedOffensesCompanion toCompanion(bool nullToAbsent) {
    return CachedOffensesCompanion(
      id: Value(id),
      label: Value(label),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
    );
  }

  factory CachedOffenseRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedOffenseRow(
      id: serializer.fromJson<String>(json['id']),
      label: serializer.fromJson<String>(json['label']),
      category: serializer.fromJson<String?>(json['category']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'label': serializer.toJson<String>(label),
      'category': serializer.toJson<String?>(category),
    };
  }

  CachedOffenseRow copyWith(
          {String? id,
          String? label,
          Value<String?> category = const Value.absent()}) =>
      CachedOffenseRow(
        id: id ?? this.id,
        label: label ?? this.label,
        category: category.present ? category.value : this.category,
      );
  CachedOffenseRow copyWithCompanion(CachedOffensesCompanion data) {
    return CachedOffenseRow(
      id: data.id.present ? data.id.value : this.id,
      label: data.label.present ? data.label.value : this.label,
      category: data.category.present ? data.category.value : this.category,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedOffenseRow(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('category: $category')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, label, category);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedOffenseRow &&
          other.id == this.id &&
          other.label == this.label &&
          other.category == this.category);
}

class CachedOffensesCompanion extends UpdateCompanion<CachedOffenseRow> {
  final Value<String> id;
  final Value<String> label;
  final Value<String?> category;
  final Value<int> rowid;
  const CachedOffensesCompanion({
    this.id = const Value.absent(),
    this.label = const Value.absent(),
    this.category = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedOffensesCompanion.insert({
    required String id,
    required String label,
    this.category = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        label = Value(label);
  static Insertable<CachedOffenseRow> custom({
    Expression<String>? id,
    Expression<String>? label,
    Expression<String>? category,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (label != null) 'label': label,
      if (category != null) 'category': category,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedOffensesCompanion copyWith(
      {Value<String>? id,
      Value<String>? label,
      Value<String?>? category,
      Value<int>? rowid}) {
    return CachedOffensesCompanion(
      id: id ?? this.id,
      label: label ?? this.label,
      category: category ?? this.category,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedOffensesCompanion(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('category: $category, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedTeachersTable extends CachedTeachers
    with TableInfo<$CachedTeachersTable, CachedTeacherRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedTeachersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fullNameMeta =
      const VerificationMeta('fullName');
  @override
  late final GeneratedColumn<String> fullName = GeneratedColumn<String>(
      'full_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, fullName];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_teachers';
  @override
  VerificationContext validateIntegrity(Insertable<CachedTeacherRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('full_name')) {
      context.handle(_fullNameMeta,
          fullName.isAcceptableOrUnknown(data['full_name']!, _fullNameMeta));
    } else if (isInserting) {
      context.missing(_fullNameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedTeacherRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedTeacherRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      fullName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}full_name'])!,
    );
  }

  @override
  $CachedTeachersTable createAlias(String alias) {
    return $CachedTeachersTable(attachedDatabase, alias);
  }
}

class CachedTeacherRow extends DataClass
    implements Insertable<CachedTeacherRow> {
  final String id;
  final String fullName;
  const CachedTeacherRow({required this.id, required this.fullName});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['full_name'] = Variable<String>(fullName);
    return map;
  }

  CachedTeachersCompanion toCompanion(bool nullToAbsent) {
    return CachedTeachersCompanion(
      id: Value(id),
      fullName: Value(fullName),
    );
  }

  factory CachedTeacherRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedTeacherRow(
      id: serializer.fromJson<String>(json['id']),
      fullName: serializer.fromJson<String>(json['fullName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fullName': serializer.toJson<String>(fullName),
    };
  }

  CachedTeacherRow copyWith({String? id, String? fullName}) => CachedTeacherRow(
        id: id ?? this.id,
        fullName: fullName ?? this.fullName,
      );
  CachedTeacherRow copyWithCompanion(CachedTeachersCompanion data) {
    return CachedTeacherRow(
      id: data.id.present ? data.id.value : this.id,
      fullName: data.fullName.present ? data.fullName.value : this.fullName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedTeacherRow(')
          ..write('id: $id, ')
          ..write('fullName: $fullName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, fullName);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedTeacherRow &&
          other.id == this.id &&
          other.fullName == this.fullName);
}

class CachedTeachersCompanion extends UpdateCompanion<CachedTeacherRow> {
  final Value<String> id;
  final Value<String> fullName;
  final Value<int> rowid;
  const CachedTeachersCompanion({
    this.id = const Value.absent(),
    this.fullName = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedTeachersCompanion.insert({
    required String id,
    required String fullName,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        fullName = Value(fullName);
  static Insertable<CachedTeacherRow> custom({
    Expression<String>? id,
    Expression<String>? fullName,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fullName != null) 'full_name': fullName,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedTeachersCompanion copyWith(
      {Value<String>? id, Value<String>? fullName, Value<int>? rowid}) {
    return CachedTeachersCompanion(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fullName.present) {
      map['full_name'] = Variable<String>(fullName.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedTeachersCompanion(')
          ..write('id: $id, ')
          ..write('fullName: $fullName, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalTapsTable extends LocalTaps
    with TableInfo<$LocalTapsTable, LocalTapRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalTapsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _studentIdMeta =
      const VerificationMeta('studentId');
  @override
  late final GeneratedColumn<String> studentId = GeneratedColumn<String>(
      'student_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _directionMeta =
      const VerificationMeta('direction');
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
      'direction', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tappedAtMeta =
      const VerificationMeta('tappedAt');
  @override
  late final GeneratedColumn<DateTime> tappedAt = GeneratedColumn<DateTime>(
      'tapped_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _schoolDayMeta =
      const VerificationMeta('schoolDay');
  @override
  late final GeneratedColumn<String> schoolDay = GeneratedColumn<String>(
      'school_day', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, studentId, direction, tappedAt, schoolDay];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_taps';
  @override
  VerificationContext validateIntegrity(Insertable<LocalTapRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('student_id')) {
      context.handle(_studentIdMeta,
          studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta));
    } else if (isInserting) {
      context.missing(_studentIdMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(_directionMeta,
          direction.isAcceptableOrUnknown(data['direction']!, _directionMeta));
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('tapped_at')) {
      context.handle(_tappedAtMeta,
          tappedAt.isAcceptableOrUnknown(data['tapped_at']!, _tappedAtMeta));
    } else if (isInserting) {
      context.missing(_tappedAtMeta);
    }
    if (data.containsKey('school_day')) {
      context.handle(_schoolDayMeta,
          schoolDay.isAcceptableOrUnknown(data['school_day']!, _schoolDayMeta));
    } else if (isInserting) {
      context.missing(_schoolDayMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalTapRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalTapRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      studentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}student_id'])!,
      direction: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}direction'])!,
      tappedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}tapped_at'])!,
      schoolDay: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}school_day'])!,
    );
  }

  @override
  $LocalTapsTable createAlias(String alias) {
    return $LocalTapsTable(attachedDatabase, alias);
  }
}

class LocalTapRow extends DataClass implements Insertable<LocalTapRow> {
  final int id;
  final String studentId;
  final String direction;
  final DateTime tappedAt;
  final String schoolDay;
  const LocalTapRow(
      {required this.id,
      required this.studentId,
      required this.direction,
      required this.tappedAt,
      required this.schoolDay});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['student_id'] = Variable<String>(studentId);
    map['direction'] = Variable<String>(direction);
    map['tapped_at'] = Variable<DateTime>(tappedAt);
    map['school_day'] = Variable<String>(schoolDay);
    return map;
  }

  LocalTapsCompanion toCompanion(bool nullToAbsent) {
    return LocalTapsCompanion(
      id: Value(id),
      studentId: Value(studentId),
      direction: Value(direction),
      tappedAt: Value(tappedAt),
      schoolDay: Value(schoolDay),
    );
  }

  factory LocalTapRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalTapRow(
      id: serializer.fromJson<int>(json['id']),
      studentId: serializer.fromJson<String>(json['studentId']),
      direction: serializer.fromJson<String>(json['direction']),
      tappedAt: serializer.fromJson<DateTime>(json['tappedAt']),
      schoolDay: serializer.fromJson<String>(json['schoolDay']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'studentId': serializer.toJson<String>(studentId),
      'direction': serializer.toJson<String>(direction),
      'tappedAt': serializer.toJson<DateTime>(tappedAt),
      'schoolDay': serializer.toJson<String>(schoolDay),
    };
  }

  LocalTapRow copyWith(
          {int? id,
          String? studentId,
          String? direction,
          DateTime? tappedAt,
          String? schoolDay}) =>
      LocalTapRow(
        id: id ?? this.id,
        studentId: studentId ?? this.studentId,
        direction: direction ?? this.direction,
        tappedAt: tappedAt ?? this.tappedAt,
        schoolDay: schoolDay ?? this.schoolDay,
      );
  LocalTapRow copyWithCompanion(LocalTapsCompanion data) {
    return LocalTapRow(
      id: data.id.present ? data.id.value : this.id,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      direction: data.direction.present ? data.direction.value : this.direction,
      tappedAt: data.tappedAt.present ? data.tappedAt.value : this.tappedAt,
      schoolDay: data.schoolDay.present ? data.schoolDay.value : this.schoolDay,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalTapRow(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('direction: $direction, ')
          ..write('tappedAt: $tappedAt, ')
          ..write('schoolDay: $schoolDay')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, studentId, direction, tappedAt, schoolDay);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalTapRow &&
          other.id == this.id &&
          other.studentId == this.studentId &&
          other.direction == this.direction &&
          other.tappedAt == this.tappedAt &&
          other.schoolDay == this.schoolDay);
}

class LocalTapsCompanion extends UpdateCompanion<LocalTapRow> {
  final Value<int> id;
  final Value<String> studentId;
  final Value<String> direction;
  final Value<DateTime> tappedAt;
  final Value<String> schoolDay;
  const LocalTapsCompanion({
    this.id = const Value.absent(),
    this.studentId = const Value.absent(),
    this.direction = const Value.absent(),
    this.tappedAt = const Value.absent(),
    this.schoolDay = const Value.absent(),
  });
  LocalTapsCompanion.insert({
    this.id = const Value.absent(),
    required String studentId,
    required String direction,
    required DateTime tappedAt,
    required String schoolDay,
  })  : studentId = Value(studentId),
        direction = Value(direction),
        tappedAt = Value(tappedAt),
        schoolDay = Value(schoolDay);
  static Insertable<LocalTapRow> custom({
    Expression<int>? id,
    Expression<String>? studentId,
    Expression<String>? direction,
    Expression<DateTime>? tappedAt,
    Expression<String>? schoolDay,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (studentId != null) 'student_id': studentId,
      if (direction != null) 'direction': direction,
      if (tappedAt != null) 'tapped_at': tappedAt,
      if (schoolDay != null) 'school_day': schoolDay,
    });
  }

  LocalTapsCompanion copyWith(
      {Value<int>? id,
      Value<String>? studentId,
      Value<String>? direction,
      Value<DateTime>? tappedAt,
      Value<String>? schoolDay}) {
    return LocalTapsCompanion(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      direction: direction ?? this.direction,
      tappedAt: tappedAt ?? this.tappedAt,
      schoolDay: schoolDay ?? this.schoolDay,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<String>(studentId.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (tappedAt.present) {
      map['tapped_at'] = Variable<DateTime>(tappedAt.value);
    }
    if (schoolDay.present) {
      map['school_day'] = Variable<String>(schoolDay.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalTapsCompanion(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('direction: $direction, ')
          ..write('tappedAt: $tappedAt, ')
          ..write('schoolDay: $schoolDay')
          ..write(')'))
        .toString();
  }
}

class $OutboxEntriesTable extends OutboxEntries
    with TableInfo<$OutboxEntriesTable, OutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _attemptsMeta =
      const VerificationMeta('attempts');
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
      'attempts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _lastErrorMeta =
      const VerificationMeta('lastError');
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
      'last_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, type, payload, createdAt, attempts, status, lastError];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_entries';
  @override
  VerificationContext validateIntegrity(Insertable<OutboxRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(_attemptsMeta,
          attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('last_error')) {
      context.handle(_lastErrorMeta,
          lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      attempts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempts'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      lastError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_error']),
    );
  }

  @override
  $OutboxEntriesTable createAlias(String alias) {
    return $OutboxEntriesTable(attachedDatabase, alias);
  }
}

class OutboxRow extends DataClass implements Insertable<OutboxRow> {
  final int id;

  /// `'tap'` or `'slip'`.
  final String type;
  final String payload;
  final DateTime createdAt;
  final int attempts;

  /// `'pending'` or `'rejected'`.
  final String status;
  final String? lastError;
  const OutboxRow(
      {required this.id,
      required this.type,
      required this.payload,
      required this.createdAt,
      required this.attempts,
      required this.status,
      this.lastError});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['type'] = Variable<String>(type);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  OutboxEntriesCompanion toCompanion(bool nullToAbsent) {
    return OutboxEntriesCompanion(
      id: Value(id),
      type: Value(type),
      payload: Value(payload),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      status: Value(status),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory OutboxRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxRow(
      id: serializer.fromJson<int>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      status: serializer.fromJson<String>(json['status']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'type': serializer.toJson<String>(type),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'status': serializer.toJson<String>(status),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  OutboxRow copyWith(
          {int? id,
          String? type,
          String? payload,
          DateTime? createdAt,
          int? attempts,
          String? status,
          Value<String?> lastError = const Value.absent()}) =>
      OutboxRow(
        id: id ?? this.id,
        type: type ?? this.type,
        payload: payload ?? this.payload,
        createdAt: createdAt ?? this.createdAt,
        attempts: attempts ?? this.attempts,
        status: status ?? this.status,
        lastError: lastError.present ? lastError.value : this.lastError,
      );
  OutboxRow copyWithCompanion(OutboxEntriesCompanion data) {
    return OutboxRow(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      status: data.status.present ? data.status.value : this.status,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRow(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('status: $status, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, type, payload, createdAt, attempts, status, lastError);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxRow &&
          other.id == this.id &&
          other.type == this.type &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.status == this.status &&
          other.lastError == this.lastError);
}

class OutboxEntriesCompanion extends UpdateCompanion<OutboxRow> {
  final Value<int> id;
  final Value<String> type;
  final Value<String> payload;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<String> status;
  final Value<String?> lastError;
  const OutboxEntriesCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.status = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  OutboxEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String type,
    required String payload,
    required DateTime createdAt,
    this.attempts = const Value.absent(),
    this.status = const Value.absent(),
    this.lastError = const Value.absent(),
  })  : type = Value(type),
        payload = Value(payload),
        createdAt = Value(createdAt);
  static Insertable<OutboxRow> custom({
    Expression<int>? id,
    Expression<String>? type,
    Expression<String>? payload,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<String>? status,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (status != null) 'status': status,
      if (lastError != null) 'last_error': lastError,
    });
  }

  OutboxEntriesCompanion copyWith(
      {Value<int>? id,
      Value<String>? type,
      Value<String>? payload,
      Value<DateTime>? createdAt,
      Value<int>? attempts,
      Value<String>? status,
      Value<String?>? lastError}) {
    return OutboxEntriesCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      status: status ?? this.status,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEntriesCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('status: $status, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta
    with TableInfo<$SyncMetaTable, SyncMetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(Insertable<SyncMetaRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncMetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetaRow(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class SyncMetaRow extends DataClass implements Insertable<SyncMetaRow> {
  final String key;
  final String value;
  const SyncMetaRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory SyncMetaRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetaRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncMetaRow copyWith({String? key, String? value}) => SyncMetaRow(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  SyncMetaRow copyWithCompanion(SyncMetaCompanion data) {
    return SyncMetaRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<SyncMetaRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetaCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return SyncMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$KioskDatabase extends GeneratedDatabase {
  _$KioskDatabase(QueryExecutor e) : super(e);
  $KioskDatabaseManager get managers => $KioskDatabaseManager(this);
  late final $CachedStudentsTable cachedStudents = $CachedStudentsTable(this);
  late final $CachedStaffTable cachedStaff = $CachedStaffTable(this);
  late final $CachedOffensesTable cachedOffenses = $CachedOffensesTable(this);
  late final $CachedTeachersTable cachedTeachers = $CachedTeachersTable(this);
  late final $LocalTapsTable localTaps = $LocalTapsTable(this);
  late final $OutboxEntriesTable outboxEntries = $OutboxEntriesTable(this);
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        cachedStudents,
        cachedStaff,
        cachedOffenses,
        cachedTeachers,
        localTaps,
        outboxEntries,
        syncMeta
      ];
}

typedef $$CachedStudentsTableCreateCompanionBuilder = CachedStudentsCompanion
    Function({
  required String id,
  required String rfidUid,
  required String fullName,
  required String studentNumber,
  required String gradeSection,
  Value<String?> course,
  Value<int> rowid,
});
typedef $$CachedStudentsTableUpdateCompanionBuilder = CachedStudentsCompanion
    Function({
  Value<String> id,
  Value<String> rfidUid,
  Value<String> fullName,
  Value<String> studentNumber,
  Value<String> gradeSection,
  Value<String?> course,
  Value<int> rowid,
});

class $$CachedStudentsTableFilterComposer
    extends Composer<_$KioskDatabase, $CachedStudentsTable> {
  $$CachedStudentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rfidUid => $composableBuilder(
      column: $table.rfidUid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fullName => $composableBuilder(
      column: $table.fullName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get studentNumber => $composableBuilder(
      column: $table.studentNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get gradeSection => $composableBuilder(
      column: $table.gradeSection, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get course => $composableBuilder(
      column: $table.course, builder: (column) => ColumnFilters(column));
}

class $$CachedStudentsTableOrderingComposer
    extends Composer<_$KioskDatabase, $CachedStudentsTable> {
  $$CachedStudentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rfidUid => $composableBuilder(
      column: $table.rfidUid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fullName => $composableBuilder(
      column: $table.fullName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get studentNumber => $composableBuilder(
      column: $table.studentNumber,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get gradeSection => $composableBuilder(
      column: $table.gradeSection,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get course => $composableBuilder(
      column: $table.course, builder: (column) => ColumnOrderings(column));
}

class $$CachedStudentsTableAnnotationComposer
    extends Composer<_$KioskDatabase, $CachedStudentsTable> {
  $$CachedStudentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rfidUid =>
      $composableBuilder(column: $table.rfidUid, builder: (column) => column);

  GeneratedColumn<String> get fullName =>
      $composableBuilder(column: $table.fullName, builder: (column) => column);

  GeneratedColumn<String> get studentNumber => $composableBuilder(
      column: $table.studentNumber, builder: (column) => column);

  GeneratedColumn<String> get gradeSection => $composableBuilder(
      column: $table.gradeSection, builder: (column) => column);

  GeneratedColumn<String> get course =>
      $composableBuilder(column: $table.course, builder: (column) => column);
}

class $$CachedStudentsTableTableManager extends RootTableManager<
    _$KioskDatabase,
    $CachedStudentsTable,
    CachedStudentRow,
    $$CachedStudentsTableFilterComposer,
    $$CachedStudentsTableOrderingComposer,
    $$CachedStudentsTableAnnotationComposer,
    $$CachedStudentsTableCreateCompanionBuilder,
    $$CachedStudentsTableUpdateCompanionBuilder,
    (
      CachedStudentRow,
      BaseReferences<_$KioskDatabase, $CachedStudentsTable, CachedStudentRow>
    ),
    CachedStudentRow,
    PrefetchHooks Function()> {
  $$CachedStudentsTableTableManager(
      _$KioskDatabase db, $CachedStudentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedStudentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedStudentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedStudentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> rfidUid = const Value.absent(),
            Value<String> fullName = const Value.absent(),
            Value<String> studentNumber = const Value.absent(),
            Value<String> gradeSection = const Value.absent(),
            Value<String?> course = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedStudentsCompanion(
            id: id,
            rfidUid: rfidUid,
            fullName: fullName,
            studentNumber: studentNumber,
            gradeSection: gradeSection,
            course: course,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String rfidUid,
            required String fullName,
            required String studentNumber,
            required String gradeSection,
            Value<String?> course = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedStudentsCompanion.insert(
            id: id,
            rfidUid: rfidUid,
            fullName: fullName,
            studentNumber: studentNumber,
            gradeSection: gradeSection,
            course: course,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedStudentsTableProcessedTableManager = ProcessedTableManager<
    _$KioskDatabase,
    $CachedStudentsTable,
    CachedStudentRow,
    $$CachedStudentsTableFilterComposer,
    $$CachedStudentsTableOrderingComposer,
    $$CachedStudentsTableAnnotationComposer,
    $$CachedStudentsTableCreateCompanionBuilder,
    $$CachedStudentsTableUpdateCompanionBuilder,
    (
      CachedStudentRow,
      BaseReferences<_$KioskDatabase, $CachedStudentsTable, CachedStudentRow>
    ),
    CachedStudentRow,
    PrefetchHooks Function()>;
typedef $$CachedStaffTableCreateCompanionBuilder = CachedStaffCompanion
    Function({
  required String id,
  required String rfidCardId,
  required String fullName,
  required String role,
  Value<int> rowid,
});
typedef $$CachedStaffTableUpdateCompanionBuilder = CachedStaffCompanion
    Function({
  Value<String> id,
  Value<String> rfidCardId,
  Value<String> fullName,
  Value<String> role,
  Value<int> rowid,
});

class $$CachedStaffTableFilterComposer
    extends Composer<_$KioskDatabase, $CachedStaffTable> {
  $$CachedStaffTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rfidCardId => $composableBuilder(
      column: $table.rfidCardId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fullName => $composableBuilder(
      column: $table.fullName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));
}

class $$CachedStaffTableOrderingComposer
    extends Composer<_$KioskDatabase, $CachedStaffTable> {
  $$CachedStaffTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rfidCardId => $composableBuilder(
      column: $table.rfidCardId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fullName => $composableBuilder(
      column: $table.fullName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));
}

class $$CachedStaffTableAnnotationComposer
    extends Composer<_$KioskDatabase, $CachedStaffTable> {
  $$CachedStaffTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rfidCardId => $composableBuilder(
      column: $table.rfidCardId, builder: (column) => column);

  GeneratedColumn<String> get fullName =>
      $composableBuilder(column: $table.fullName, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);
}

class $$CachedStaffTableTableManager extends RootTableManager<
    _$KioskDatabase,
    $CachedStaffTable,
    CachedStaffRow,
    $$CachedStaffTableFilterComposer,
    $$CachedStaffTableOrderingComposer,
    $$CachedStaffTableAnnotationComposer,
    $$CachedStaffTableCreateCompanionBuilder,
    $$CachedStaffTableUpdateCompanionBuilder,
    (
      CachedStaffRow,
      BaseReferences<_$KioskDatabase, $CachedStaffTable, CachedStaffRow>
    ),
    CachedStaffRow,
    PrefetchHooks Function()> {
  $$CachedStaffTableTableManager(_$KioskDatabase db, $CachedStaffTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedStaffTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedStaffTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedStaffTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> rfidCardId = const Value.absent(),
            Value<String> fullName = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedStaffCompanion(
            id: id,
            rfidCardId: rfidCardId,
            fullName: fullName,
            role: role,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String rfidCardId,
            required String fullName,
            required String role,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedStaffCompanion.insert(
            id: id,
            rfidCardId: rfidCardId,
            fullName: fullName,
            role: role,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedStaffTableProcessedTableManager = ProcessedTableManager<
    _$KioskDatabase,
    $CachedStaffTable,
    CachedStaffRow,
    $$CachedStaffTableFilterComposer,
    $$CachedStaffTableOrderingComposer,
    $$CachedStaffTableAnnotationComposer,
    $$CachedStaffTableCreateCompanionBuilder,
    $$CachedStaffTableUpdateCompanionBuilder,
    (
      CachedStaffRow,
      BaseReferences<_$KioskDatabase, $CachedStaffTable, CachedStaffRow>
    ),
    CachedStaffRow,
    PrefetchHooks Function()>;
typedef $$CachedOffensesTableCreateCompanionBuilder = CachedOffensesCompanion
    Function({
  required String id,
  required String label,
  Value<String?> category,
  Value<int> rowid,
});
typedef $$CachedOffensesTableUpdateCompanionBuilder = CachedOffensesCompanion
    Function({
  Value<String> id,
  Value<String> label,
  Value<String?> category,
  Value<int> rowid,
});

class $$CachedOffensesTableFilterComposer
    extends Composer<_$KioskDatabase, $CachedOffensesTable> {
  $$CachedOffensesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));
}

class $$CachedOffensesTableOrderingComposer
    extends Composer<_$KioskDatabase, $CachedOffensesTable> {
  $$CachedOffensesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));
}

class $$CachedOffensesTableAnnotationComposer
    extends Composer<_$KioskDatabase, $CachedOffensesTable> {
  $$CachedOffensesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);
}

class $$CachedOffensesTableTableManager extends RootTableManager<
    _$KioskDatabase,
    $CachedOffensesTable,
    CachedOffenseRow,
    $$CachedOffensesTableFilterComposer,
    $$CachedOffensesTableOrderingComposer,
    $$CachedOffensesTableAnnotationComposer,
    $$CachedOffensesTableCreateCompanionBuilder,
    $$CachedOffensesTableUpdateCompanionBuilder,
    (
      CachedOffenseRow,
      BaseReferences<_$KioskDatabase, $CachedOffensesTable, CachedOffenseRow>
    ),
    CachedOffenseRow,
    PrefetchHooks Function()> {
  $$CachedOffensesTableTableManager(
      _$KioskDatabase db, $CachedOffensesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedOffensesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedOffensesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedOffensesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> label = const Value.absent(),
            Value<String?> category = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedOffensesCompanion(
            id: id,
            label: label,
            category: category,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String label,
            Value<String?> category = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedOffensesCompanion.insert(
            id: id,
            label: label,
            category: category,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedOffensesTableProcessedTableManager = ProcessedTableManager<
    _$KioskDatabase,
    $CachedOffensesTable,
    CachedOffenseRow,
    $$CachedOffensesTableFilterComposer,
    $$CachedOffensesTableOrderingComposer,
    $$CachedOffensesTableAnnotationComposer,
    $$CachedOffensesTableCreateCompanionBuilder,
    $$CachedOffensesTableUpdateCompanionBuilder,
    (
      CachedOffenseRow,
      BaseReferences<_$KioskDatabase, $CachedOffensesTable, CachedOffenseRow>
    ),
    CachedOffenseRow,
    PrefetchHooks Function()>;
typedef $$CachedTeachersTableCreateCompanionBuilder = CachedTeachersCompanion
    Function({
  required String id,
  required String fullName,
  Value<int> rowid,
});
typedef $$CachedTeachersTableUpdateCompanionBuilder = CachedTeachersCompanion
    Function({
  Value<String> id,
  Value<String> fullName,
  Value<int> rowid,
});

class $$CachedTeachersTableFilterComposer
    extends Composer<_$KioskDatabase, $CachedTeachersTable> {
  $$CachedTeachersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fullName => $composableBuilder(
      column: $table.fullName, builder: (column) => ColumnFilters(column));
}

class $$CachedTeachersTableOrderingComposer
    extends Composer<_$KioskDatabase, $CachedTeachersTable> {
  $$CachedTeachersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fullName => $composableBuilder(
      column: $table.fullName, builder: (column) => ColumnOrderings(column));
}

class $$CachedTeachersTableAnnotationComposer
    extends Composer<_$KioskDatabase, $CachedTeachersTable> {
  $$CachedTeachersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fullName =>
      $composableBuilder(column: $table.fullName, builder: (column) => column);
}

class $$CachedTeachersTableTableManager extends RootTableManager<
    _$KioskDatabase,
    $CachedTeachersTable,
    CachedTeacherRow,
    $$CachedTeachersTableFilterComposer,
    $$CachedTeachersTableOrderingComposer,
    $$CachedTeachersTableAnnotationComposer,
    $$CachedTeachersTableCreateCompanionBuilder,
    $$CachedTeachersTableUpdateCompanionBuilder,
    (
      CachedTeacherRow,
      BaseReferences<_$KioskDatabase, $CachedTeachersTable, CachedTeacherRow>
    ),
    CachedTeacherRow,
    PrefetchHooks Function()> {
  $$CachedTeachersTableTableManager(
      _$KioskDatabase db, $CachedTeachersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedTeachersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedTeachersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedTeachersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> fullName = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedTeachersCompanion(
            id: id,
            fullName: fullName,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String fullName,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedTeachersCompanion.insert(
            id: id,
            fullName: fullName,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedTeachersTableProcessedTableManager = ProcessedTableManager<
    _$KioskDatabase,
    $CachedTeachersTable,
    CachedTeacherRow,
    $$CachedTeachersTableFilterComposer,
    $$CachedTeachersTableOrderingComposer,
    $$CachedTeachersTableAnnotationComposer,
    $$CachedTeachersTableCreateCompanionBuilder,
    $$CachedTeachersTableUpdateCompanionBuilder,
    (
      CachedTeacherRow,
      BaseReferences<_$KioskDatabase, $CachedTeachersTable, CachedTeacherRow>
    ),
    CachedTeacherRow,
    PrefetchHooks Function()>;
typedef $$LocalTapsTableCreateCompanionBuilder = LocalTapsCompanion Function({
  Value<int> id,
  required String studentId,
  required String direction,
  required DateTime tappedAt,
  required String schoolDay,
});
typedef $$LocalTapsTableUpdateCompanionBuilder = LocalTapsCompanion Function({
  Value<int> id,
  Value<String> studentId,
  Value<String> direction,
  Value<DateTime> tappedAt,
  Value<String> schoolDay,
});

class $$LocalTapsTableFilterComposer
    extends Composer<_$KioskDatabase, $LocalTapsTable> {
  $$LocalTapsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get direction => $composableBuilder(
      column: $table.direction, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get tappedAt => $composableBuilder(
      column: $table.tappedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get schoolDay => $composableBuilder(
      column: $table.schoolDay, builder: (column) => ColumnFilters(column));
}

class $$LocalTapsTableOrderingComposer
    extends Composer<_$KioskDatabase, $LocalTapsTable> {
  $$LocalTapsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get direction => $composableBuilder(
      column: $table.direction, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get tappedAt => $composableBuilder(
      column: $table.tappedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get schoolDay => $composableBuilder(
      column: $table.schoolDay, builder: (column) => ColumnOrderings(column));
}

class $$LocalTapsTableAnnotationComposer
    extends Composer<_$KioskDatabase, $LocalTapsTable> {
  $$LocalTapsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<DateTime> get tappedAt =>
      $composableBuilder(column: $table.tappedAt, builder: (column) => column);

  GeneratedColumn<String> get schoolDay =>
      $composableBuilder(column: $table.schoolDay, builder: (column) => column);
}

class $$LocalTapsTableTableManager extends RootTableManager<
    _$KioskDatabase,
    $LocalTapsTable,
    LocalTapRow,
    $$LocalTapsTableFilterComposer,
    $$LocalTapsTableOrderingComposer,
    $$LocalTapsTableAnnotationComposer,
    $$LocalTapsTableCreateCompanionBuilder,
    $$LocalTapsTableUpdateCompanionBuilder,
    (
      LocalTapRow,
      BaseReferences<_$KioskDatabase, $LocalTapsTable, LocalTapRow>
    ),
    LocalTapRow,
    PrefetchHooks Function()> {
  $$LocalTapsTableTableManager(_$KioskDatabase db, $LocalTapsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalTapsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalTapsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalTapsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> studentId = const Value.absent(),
            Value<String> direction = const Value.absent(),
            Value<DateTime> tappedAt = const Value.absent(),
            Value<String> schoolDay = const Value.absent(),
          }) =>
              LocalTapsCompanion(
            id: id,
            studentId: studentId,
            direction: direction,
            tappedAt: tappedAt,
            schoolDay: schoolDay,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String studentId,
            required String direction,
            required DateTime tappedAt,
            required String schoolDay,
          }) =>
              LocalTapsCompanion.insert(
            id: id,
            studentId: studentId,
            direction: direction,
            tappedAt: tappedAt,
            schoolDay: schoolDay,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalTapsTableProcessedTableManager = ProcessedTableManager<
    _$KioskDatabase,
    $LocalTapsTable,
    LocalTapRow,
    $$LocalTapsTableFilterComposer,
    $$LocalTapsTableOrderingComposer,
    $$LocalTapsTableAnnotationComposer,
    $$LocalTapsTableCreateCompanionBuilder,
    $$LocalTapsTableUpdateCompanionBuilder,
    (
      LocalTapRow,
      BaseReferences<_$KioskDatabase, $LocalTapsTable, LocalTapRow>
    ),
    LocalTapRow,
    PrefetchHooks Function()>;
typedef $$OutboxEntriesTableCreateCompanionBuilder = OutboxEntriesCompanion
    Function({
  Value<int> id,
  required String type,
  required String payload,
  required DateTime createdAt,
  Value<int> attempts,
  Value<String> status,
  Value<String?> lastError,
});
typedef $$OutboxEntriesTableUpdateCompanionBuilder = OutboxEntriesCompanion
    Function({
  Value<int> id,
  Value<String> type,
  Value<String> payload,
  Value<DateTime> createdAt,
  Value<int> attempts,
  Value<String> status,
  Value<String?> lastError,
});

class $$OutboxEntriesTableFilterComposer
    extends Composer<_$KioskDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnFilters(column));
}

class $$OutboxEntriesTableOrderingComposer
    extends Composer<_$KioskDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnOrderings(column));
}

class $$OutboxEntriesTableAnnotationComposer
    extends Composer<_$KioskDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$OutboxEntriesTableTableManager extends RootTableManager<
    _$KioskDatabase,
    $OutboxEntriesTable,
    OutboxRow,
    $$OutboxEntriesTableFilterComposer,
    $$OutboxEntriesTableOrderingComposer,
    $$OutboxEntriesTableAnnotationComposer,
    $$OutboxEntriesTableCreateCompanionBuilder,
    $$OutboxEntriesTableUpdateCompanionBuilder,
    (
      OutboxRow,
      BaseReferences<_$KioskDatabase, $OutboxEntriesTable, OutboxRow>
    ),
    OutboxRow,
    PrefetchHooks Function()> {
  $$OutboxEntriesTableTableManager(
      _$KioskDatabase db, $OutboxEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
          }) =>
              OutboxEntriesCompanion(
            id: id,
            type: type,
            payload: payload,
            createdAt: createdAt,
            attempts: attempts,
            status: status,
            lastError: lastError,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String type,
            required String payload,
            required DateTime createdAt,
            Value<int> attempts = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
          }) =>
              OutboxEntriesCompanion.insert(
            id: id,
            type: type,
            payload: payload,
            createdAt: createdAt,
            attempts: attempts,
            status: status,
            lastError: lastError,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$OutboxEntriesTableProcessedTableManager = ProcessedTableManager<
    _$KioskDatabase,
    $OutboxEntriesTable,
    OutboxRow,
    $$OutboxEntriesTableFilterComposer,
    $$OutboxEntriesTableOrderingComposer,
    $$OutboxEntriesTableAnnotationComposer,
    $$OutboxEntriesTableCreateCompanionBuilder,
    $$OutboxEntriesTableUpdateCompanionBuilder,
    (
      OutboxRow,
      BaseReferences<_$KioskDatabase, $OutboxEntriesTable, OutboxRow>
    ),
    OutboxRow,
    PrefetchHooks Function()>;
typedef $$SyncMetaTableCreateCompanionBuilder = SyncMetaCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SyncMetaTableUpdateCompanionBuilder = SyncMetaCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SyncMetaTableFilterComposer
    extends Composer<_$KioskDatabase, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$KioskDatabase, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$KioskDatabase, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncMetaTableTableManager extends RootTableManager<
    _$KioskDatabase,
    $SyncMetaTable,
    SyncMetaRow,
    $$SyncMetaTableFilterComposer,
    $$SyncMetaTableOrderingComposer,
    $$SyncMetaTableAnnotationComposer,
    $$SyncMetaTableCreateCompanionBuilder,
    $$SyncMetaTableUpdateCompanionBuilder,
    (SyncMetaRow, BaseReferences<_$KioskDatabase, $SyncMetaTable, SyncMetaRow>),
    SyncMetaRow,
    PrefetchHooks Function()> {
  $$SyncMetaTableTableManager(_$KioskDatabase db, $SyncMetaTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncMetaCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncMetaCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncMetaTableProcessedTableManager = ProcessedTableManager<
    _$KioskDatabase,
    $SyncMetaTable,
    SyncMetaRow,
    $$SyncMetaTableFilterComposer,
    $$SyncMetaTableOrderingComposer,
    $$SyncMetaTableAnnotationComposer,
    $$SyncMetaTableCreateCompanionBuilder,
    $$SyncMetaTableUpdateCompanionBuilder,
    (SyncMetaRow, BaseReferences<_$KioskDatabase, $SyncMetaTable, SyncMetaRow>),
    SyncMetaRow,
    PrefetchHooks Function()>;

class $KioskDatabaseManager {
  final _$KioskDatabase _db;
  $KioskDatabaseManager(this._db);
  $$CachedStudentsTableTableManager get cachedStudents =>
      $$CachedStudentsTableTableManager(_db, _db.cachedStudents);
  $$CachedStaffTableTableManager get cachedStaff =>
      $$CachedStaffTableTableManager(_db, _db.cachedStaff);
  $$CachedOffensesTableTableManager get cachedOffenses =>
      $$CachedOffensesTableTableManager(_db, _db.cachedOffenses);
  $$CachedTeachersTableTableManager get cachedTeachers =>
      $$CachedTeachersTableTableManager(_db, _db.cachedTeachers);
  $$LocalTapsTableTableManager get localTaps =>
      $$LocalTapsTableTableManager(_db, _db.localTaps);
  $$OutboxEntriesTableTableManager get outboxEntries =>
      $$OutboxEntriesTableTableManager(_db, _db.outboxEntries);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
}
