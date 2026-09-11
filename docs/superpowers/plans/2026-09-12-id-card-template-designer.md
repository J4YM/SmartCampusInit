# ID Card Template Designer + Print Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a full drag-and-drop ID card template designer (matching IDAssist's Design ID Layout module) inside IT Technician Dashboard, a software signature-capture step, template-driven printing that replaces the current hardcoded card layout, and a Windows installer for the main dashboard build.

**Architecture:** One shared, pure-Dart element model (`IdCardTemplateElement`, living in `packages/rfid_management_module` so both the editor and the root app's renderer can use it) stores every element's position in PDF point units — the single canonical coordinate space. Two renderers read the same element list: a Flutter-widget canvas for editing, and a `pdf`-package renderer for printing/preview. `IdCardTemplatesRepository` (root app) does the Supabase I/O; the editor and print dialog stay Supabase-free, wired via callbacks from `ItTechnicianConnectedPage`, matching this codebase's established connected-page pattern.

**Tech Stack:** Flutter/Dart, Supabase (Postgres + PostgREST + RLS + Storage), the `pdf`/`printing` packages (already dependencies), the `signature` package (new dependency, pure-Dart drawing canvas), Inno Setup for the Windows installer.

**Spec:** docs/superpowers/specs/2026-09-12-id-card-template-designer-design.md

## Global Constraints

- SQL is shown in this plan for the user's manual execution in the Supabase SQL Editor — never auto-run by any task.
- No platform-conditional (`kIsWeb`) code anywhere in this feature — it must work identically on web and Windows, matching how the existing webcam photo capture already works cross-platform via the `camera` plugin's web support.
- Every `IdCardTemplateElement`'s `x`/`y`/`width`/`height` is always in PDF point units (72pt/inch), against the CR-80 card's real physical size (3.375in × 2.125in = 243pt × 153pt = `idCardWidthPt`/`idCardHeightPt`). This is the single canonical coordinate space, in storage AND in the editor's in-memory state — only the editor's on-screen zoom is presentation-layer.
- The Fingerprint element type and any Topaz hardware SDK integration are explicitly out of scope per the spec's Non-goals — do not add either.
- No group-resize (resize handles only appear on a single selection), no OS-level clipboard (copy/paste is in-memory within the open editor session), no autosave (an explicit Save action only).
- The existing `guardianName` field (derived from `parent_student_links`, not a plain `students` column) is explicitly NOT touched by this plan — it has a known, pre-existing, unrelated gap (entered on the registration form but never actually persisted to any column) that is out of scope to fix here. This plan only adds the NEW `guardian_contact_no` column/field, which IS fully wired end-to-end.
- Every new Supabase table/bucket gets both `to authenticated` AND `to anon` RLS policies from the start (the `using (true)`/`with check (true)` idiom already established repeatedly in this codebase, e.g. `add_audit_logs_anon_rls.sql`, `add_rfid_assignment_requests_schema.sql`) — static demo accounts never hold a real Supabase Auth session, so every request from a demo session hits Postgres as `anon`, not `authenticated`.
- Signature-guard tests for every new/modified repository method (construct with a fake Supabase URL, tear off the method against its exact function-type signature, never actually call it) — matches this codebase's established convention.

---

### Task 1: Schema — templates table, student columns, media storage

**Files:**
- Create: `supabase/add_id_card_templates_schema.sql`
- Create: `supabase/add_id_card_student_columns.sql`
- Create: `supabase/add_id_card_media_storage.sql`

**Interfaces:**
- Produces: `public.id_card_templates` table (`id, name, front_layout jsonb, back_layout jsonb, created_by, created_at, updated_at`), `public.students.guardian_contact_no`, `public.students.signature_path`, storage buckets `student-signatures` and `id-card-template-images`.
- Consumes: nothing from other tasks.

**Context:** This app's convention is SQL files shown to the user for manual execution in the Supabase SQL Editor — never run automatically. Follow `supabase/add_rfid_assignment_requests_schema.sql`'s exact RLS idiom (both `to authenticated` and `to anon` policies, since static demo accounts hit Supabase as `anon`) and `supabase/add_student_photos_storage.sql`'s exact private-bucket-plus-signed-URL pattern for the new storage buckets.

- [ ] **Step 1: Write the templates table SQL**

```sql
-- supabase/add_id_card_templates_schema.sql
--
-- Saved ID card templates for IT Technician's Design ID Layout editor —
-- each row is one named template with independent front/back element
-- layouts (opaque jsonb; only Dart code ever reads/writes individual
-- element fields, so no relational schema for the layout's contents —
-- see packages/rfid_management_module/lib/id_card_template.dart for the
-- element shape).
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

create table if not exists public.id_card_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  front_layout jsonb not null default '[]'::jsonb,
  back_layout jsonb not null default '[]'::jsonb,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.id_card_templates enable row level security;

drop policy if exists "id_card_templates_select" on public.id_card_templates;
create policy "id_card_templates_select"
on public.id_card_templates for select
to authenticated
using (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role));

drop policy if exists "id_card_templates_insert" on public.id_card_templates;
create policy "id_card_templates_insert"
on public.id_card_templates for insert
to authenticated
with check (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role));

drop policy if exists "id_card_templates_update" on public.id_card_templates;
create policy "id_card_templates_update"
on public.id_card_templates for update
to authenticated
using (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role))
with check (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role));

drop policy if exists "id_card_templates_delete" on public.id_card_templates;
create policy "id_card_templates_delete"
on public.id_card_templates for delete
to authenticated
using (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role));

-- Static demo accounts (lib/auth/static_demo_accounts.dart) never
-- authenticate via real Supabase Auth, so every request from a demo
-- session goes out as Postgres role anon, not authenticated — without
-- these, every method on IdCardTemplatesRepository would silently
-- see/affect zero rows for the ittech.demo account. Same tradeoff as
-- add_audit_logs_anon_rls.sql: fully open to anyone holding the public
-- anon key. Fine for local development/demo; tighten before production.

drop policy if exists "id_card_templates_anon_select" on public.id_card_templates;
create policy "id_card_templates_anon_select"
on public.id_card_templates for select
to anon
using (true);

drop policy if exists "id_card_templates_anon_insert" on public.id_card_templates;
create policy "id_card_templates_anon_insert"
on public.id_card_templates for insert
to anon
with check (true);

drop policy if exists "id_card_templates_anon_update" on public.id_card_templates;
create policy "id_card_templates_anon_update"
on public.id_card_templates for update
to anon
using (true)
with check (true);

drop policy if exists "id_card_templates_anon_delete" on public.id_card_templates;
create policy "id_card_templates_anon_delete"
on public.id_card_templates for delete
to anon
using (true);

-- Keeps updated_at current on every layout/name change — the print
-- flow's template picker defaults to the most-recently-updated template
-- and relies on this being accurate.
create or replace function public.set_id_card_templates_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_id_card_templates_updated_at on public.id_card_templates;
create trigger trg_id_card_templates_updated_at
before update on public.id_card_templates
for each row
execute function public.set_id_card_templates_updated_at();
```

- [ ] **Step 2: Write the student columns SQL**

```sql
-- supabase/add_id_card_student_columns.sql
--
-- Two new plain columns on `students`, both entered directly on the
-- IT Technician registration form (see RfidRegistrationForm) — neither
-- depends on a linked parent-portal account existing:
--   guardian_contact_no — the ID card back's "Contact No" (emergency
--     contact) field. Distinct from the existing, derived `guardianName`
--     (sourced from parent_student_links elsewhere, out of scope here —
--     see this plan's Global Constraints) — this is a new, independently
--     entered and persisted column.
--   signature_path — Storage object path of the student's captured
--     signature, mirroring the existing photo_path column exactly.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

alter table public.students
  add column if not exists guardian_contact_no text;

alter table public.students
  add column if not exists signature_path text;
```

- [ ] **Step 3: Write the media storage SQL**

```sql
-- supabase/add_id_card_media_storage.sql
--
-- Two new private storage buckets for the ID card template designer:
--   student-signatures — one captured signature image per student,
--     mirroring add_student_photos_storage.sql's student-photos bucket
--     exactly (same private-bucket-plus-signed-URL pattern).
--   id-card-template-images — static images (e.g. school logos) used by
--     Image-type template elements. Not per-student — shared across
--     templates, so no student_id-shaped path convention.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

insert into storage.buckets (id, name, public)
values ('student-signatures', 'student-signatures', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('id-card-template-images', 'id-card-template-images', false)
on conflict (id) do nothing;

drop policy if exists "Authenticated can read student signatures" on storage.objects;
create policy "Authenticated can read student signatures"
on storage.objects for select
to authenticated
using (bucket_id = 'student-signatures');

drop policy if exists "Authenticated can upload student signatures" on storage.objects;
create policy "Authenticated can upload student signatures"
on storage.objects for insert
to authenticated
with check (bucket_id = 'student-signatures');

drop policy if exists "Authenticated can replace student signatures" on storage.objects;
create policy "Authenticated can replace student signatures"
on storage.objects for update
to authenticated
using (bucket_id = 'student-signatures')
with check (bucket_id = 'student-signatures');

drop policy if exists "Authenticated can read template images" on storage.objects;
create policy "Authenticated can read template images"
on storage.objects for select
to authenticated
using (bucket_id = 'id-card-template-images');

drop policy if exists "Authenticated can upload template images" on storage.objects;
create policy "Authenticated can upload template images"
on storage.objects for insert
to authenticated
with check (bucket_id = 'id-card-template-images');

drop policy if exists "Authenticated can replace template images" on storage.objects;
create policy "Authenticated can replace template images"
on storage.objects for update
to authenticated
using (bucket_id = 'id-card-template-images')
with check (bucket_id = 'id-card-template-images');

-- The static demo accounts (lib/auth/static_demo_accounts.dart) never
-- authenticate via real Supabase Auth, so every storage request from a
-- demo session goes out as Postgres role anon, not authenticated —
-- without these, the ittech.demo account could never capture a
-- signature or upload a template image. Same tradeoff as
-- add_audit_logs_anon_rls.sql. Fine for local development/demo; tighten
-- before production. (The existing student-photos bucket in
-- add_student_photos_storage.sql predates this pattern and doesn't have
-- these — out of scope to fix here, since it's a pre-existing,
-- unrelated bucket.)

drop policy if exists "Anon can read student signatures" on storage.objects;
create policy "Anon can read student signatures"
on storage.objects for select
to anon
using (bucket_id = 'student-signatures');

drop policy if exists "Anon can upload student signatures" on storage.objects;
create policy "Anon can upload student signatures"
on storage.objects for insert
to anon
with check (bucket_id = 'student-signatures');

drop policy if exists "Anon can replace student signatures" on storage.objects;
create policy "Anon can replace student signatures"
on storage.objects for update
to anon
using (bucket_id = 'student-signatures')
with check (bucket_id = 'student-signatures');

drop policy if exists "Anon can read template images" on storage.objects;
create policy "Anon can read template images"
on storage.objects for select
to anon
using (bucket_id = 'id-card-template-images');

drop policy if exists "Anon can upload template images" on storage.objects;
create policy "Anon can upload template images"
on storage.objects for insert
to anon
with check (bucket_id = 'id-card-template-images');

drop policy if exists "Anon can replace template images" on storage.objects;
create policy "Anon can replace template images"
on storage.objects for update
to anon
using (bucket_id = 'id-card-template-images')
with check (bucket_id = 'id-card-template-images');
```

- [ ] **Step 4: Commit**

```bash
git add supabase/add_id_card_templates_schema.sql supabase/add_id_card_student_columns.sql supabase/add_id_card_media_storage.sql
git commit -m "feat: add id_card_templates schema, student columns, media storage"
```

Relay the full content of all three SQL files to the user for manual execution in the Supabase SQL Editor — do not attempt to run them yourself.

---

### Task 2: Shared element model + `IdCardTemplatesRepository`

**Files:**
- Create: `packages/rfid_management_module/lib/id_card_template.dart`
- Modify: `packages/rfid_management_module/lib/rfid_management_module.dart`
- Create: `lib/data/id_card_templates_repository.dart`
- Test: `packages/rfid_management_module/test/id_card_template_test.dart`
- Test: `test/id_card_templates_repository_test.dart`

**Interfaces:**
- Consumes: Task 1's `id_card_templates` table (`id, name, front_layout, back_layout, updated_at`) and the two new storage buckets.
- Produces: `IdCardElementType` enum, `IdDataFieldKey` enum, `IdCardTemplateElement{id, type, x, y, width, height, rotation, zIndex, textContent, fontFamily, fontSize, color, textAlign, imagePath, fieldKey, fillColor, strokeColor, strokeWidth, cornerRadius}` with `copyWith`/`toJson`/`fromJson`, `IdCardTemplateSummary{id, name, updatedAt}`, `IdCardTemplateDetail{id, name, frontLayout, backLayout}`, `idCardWidthPt`/`idCardHeightPt` constants — ALL of these live in the `rfid_management_module` package (pure Dart, no Flutter/Supabase imports) so every later task (editor UI, print dialog, PDF renderer) can use them regardless of which side of the package/root-app boundary it's on. `IdCardTemplatesRepository{fetchTemplates, fetchTemplate, createTemplate, updateTemplateLayouts, renameTemplate, deleteTemplate, uploadTemplateImage, fetchTemplateImageUrl}` in `lib/data/` does the actual Supabase I/O using those shared types directly — it defines no types of its own.

**Context:** This app's package layout is one-way: the root app (`lib/`) may import from `packages/rfid_management_module`, but that package may never import from `lib/`. Because the SAME element data is used for storage, editing, AND rendering (per the spec's "one element model, two renderers" architecture), there's no reason to duplicate it the way `RfidRequestModel`/`RfidRequestRowModel` were duplicated in the RFID assignment requests feature — one shared model, defined in the package, is enough.

- [ ] **Step 1: Write the shared element/template model**

```dart
// packages/rfid_management_module/lib/id_card_template.dart
//
// The single shared data shape for an ID card template's front/back
// layout — used by the template editor (this package), by
// IdCardTemplatesRepository (lib/data, does the Supabase I/O), and by
// the PDF renderer (lib/documents). Deliberately pure Dart (no
// Flutter/Supabase imports) so it's usable from every layer without
// pulling in dependencies those layers don't need.

/// One element's kind — matches IDAssist's own Design ID Layout toolbox,
/// minus Fingerprint (out of scope — no fingerprint hardware exists
/// anywhere in this app).
enum IdCardElementType {
  staticText,
  image,
  idData,
  idPicture,
  signature,
  rectangle,
  roundedRect,
  ellipse,
  line,
}

/// Which student field an `idData` element displays.
enum IdDataFieldKey {
  firstName,
  middleInitial,
  lastName,
  studentNumber,
  course,
  section,
  yearLevel,
  guardianName,
  guardianContactNo,
}

/// One positioned element on a template's front or back. `x`/`y`/`width`/
/// `height` are always in PDF point units (72pt/inch) against the CR-80
/// card's real physical size ([idCardWidthPt] x [idCardHeightPt]) — the
/// single canonical coordinate space this whole feature stores and edits
/// in. Every field below `zIndex` is optional and only meaningful for
/// certain [type]s — see each field's doc comment.
class IdCardTemplateElement {
  const IdCardTemplateElement({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.zIndex = 0,
    this.textContent,
    this.fontFamily,
    this.fontSize,
    this.color,
    this.textAlign,
    this.imagePath,
    this.fieldKey,
    this.fillColor,
    this.strokeColor,
    this.strokeWidth,
    this.cornerRadius,
  });

  final String id;
  final IdCardElementType type;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final int zIndex;

  /// `staticText`/`idData` only.
  final String? textContent;
  final String? fontFamily;
  final double? fontSize;

  /// ARGB int (`Color.value`) — `staticText`/`idData`'s text color.
  final int? color;

  /// `staticText`/`idData` only: 'left' | 'center' | 'right'.
  final String? textAlign;

  /// `image` only — Storage object path in the `id-card-template-images`
  /// bucket.
  final String? imagePath;

  /// `idData` only — which student field this element displays.
  final IdDataFieldKey? fieldKey;

  /// `rectangle`/`roundedRect`/`ellipse` only. ARGB int.
  final int? fillColor;

  /// `rectangle`/`roundedRect`/`ellipse`/`line` only. ARGB int.
  final int? strokeColor;
  final double? strokeWidth;

  /// `roundedRect` only.
  final double? cornerRadius;

  IdCardTemplateElement copyWith({
    String? id,
    IdCardElementType? type,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    int? zIndex,
    String? textContent,
    String? fontFamily,
    double? fontSize,
    int? color,
    String? textAlign,
    String? imagePath,
    IdDataFieldKey? fieldKey,
    int? fillColor,
    int? strokeColor,
    double? strokeWidth,
    double? cornerRadius,
  }) {
    return IdCardTemplateElement(
      id: id ?? this.id,
      type: type ?? this.type,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      zIndex: zIndex ?? this.zIndex,
      textContent: textContent ?? this.textContent,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      textAlign: textAlign ?? this.textAlign,
      imagePath: imagePath ?? this.imagePath,
      fieldKey: fieldKey ?? this.fieldKey,
      fillColor: fillColor ?? this.fillColor,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      cornerRadius: cornerRadius ?? this.cornerRadius,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'rotation': rotation,
      'zIndex': zIndex,
      if (textContent != null) 'textContent': textContent,
      if (fontFamily != null) 'fontFamily': fontFamily,
      if (fontSize != null) 'fontSize': fontSize,
      if (color != null) 'color': color,
      if (textAlign != null) 'textAlign': textAlign,
      if (imagePath != null) 'imagePath': imagePath,
      if (fieldKey != null) 'fieldKey': fieldKey!.name,
      if (fillColor != null) 'fillColor': fillColor,
      if (strokeColor != null) 'strokeColor': strokeColor,
      if (strokeWidth != null) 'strokeWidth': strokeWidth,
      if (cornerRadius != null) 'cornerRadius': cornerRadius,
    };
  }

  factory IdCardTemplateElement.fromJson(Map<String, dynamic> json) {
    return IdCardTemplateElement(
      id: json['id'] as String,
      type: IdCardElementType.values.byName(json['type'] as String),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      textContent: json['textContent'] as String?,
      fontFamily: json['fontFamily'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      color: (json['color'] as num?)?.toInt(),
      textAlign: json['textAlign'] as String?,
      imagePath: json['imagePath'] as String?,
      fieldKey: json['fieldKey'] == null
          ? null
          : IdDataFieldKey.values.byName(json['fieldKey'] as String),
      fillColor: (json['fillColor'] as num?)?.toInt(),
      strokeColor: (json['strokeColor'] as num?)?.toInt(),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble(),
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble(),
    );
  }
}

/// The CR-80 card's real physical size in PDF points (72pt/inch) — the
/// canonical coordinate space every element's x/y/width/height is stored
/// and edited in.
const double idCardWidthPt = 3.375 * 72;
const double idCardHeightPt = 2.125 * 72;

/// One row of the template picker/list — no layout data, just enough to
/// display and sort (`fetchTemplates` orders by `updatedAt` descending).
class IdCardTemplateSummary {
  const IdCardTemplateSummary({
    required this.id,
    required this.name,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final DateTime updatedAt;
}

/// A template's full front/back layouts — what the editor loads and
/// saves, and what the print flow's renderer consumes.
class IdCardTemplateDetail {
  const IdCardTemplateDetail({
    required this.id,
    required this.name,
    required this.frontLayout,
    required this.backLayout,
  });

  final String id;
  final String name;
  final List<IdCardTemplateElement> frontLayout;
  final List<IdCardTemplateElement> backLayout;
}
```

- [ ] **Step 2: Export it from the package barrel**

Add to `packages/rfid_management_module/lib/rfid_management_module.dart`:
```dart
export 'id_card_template.dart';
```
(Alphabetical position: right after `export 'rfid_student_row.dart';` if that line exists, otherwise anywhere among the other top-level exports before the `ui/` ones — check the file's current ordering first.)

- [ ] **Step 3: Write the model round-trip test**

```dart
// packages/rfid_management_module/test/id_card_template_test.dart
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
```

- [ ] **Step 4: Run the package test**

Run: `flutter test packages/rfid_management_module/test/id_card_template_test.dart` (from the worktree root — do NOT `cd` into the package first; this environment has a known issue where running tests from inside a package resolves a stale, incompatible `google_fonts` version and fails to compile for unrelated reasons).
Expected: 3 tests PASS.

- [ ] **Step 5: Write `IdCardTemplatesRepository`**

```dart
// lib/data/id_card_templates_repository.dart
import 'dart:typed_data';

import 'package:rfid_management_module/rfid_management_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// CRUD for `id_card_templates` plus template-image storage — the ONE
/// shared repository for the template designer, consumed by the template
/// list screen, the editor, and the print flow. Never duplicated
/// per-caller. Defines no types of its own — every type it returns or
/// consumes lives in package:rfid_management_module/id_card_template.dart
/// so the editor UI (in that same package) never needs a second,
/// duplicate model.
class IdCardTemplatesRepository {
  IdCardTemplatesRepository(this._client);
  final SupabaseClient _client;

  static const _templateImagesBucket = 'id-card-template-images';

  Future<List<IdCardTemplateSummary>> fetchTemplates() async {
    final rows = await _client
        .from('id_card_templates')
        .select('id, name, updated_at')
        .order('updated_at', ascending: false);
    return (rows as List)
        .map((row) => IdCardTemplateSummary(
              id: row['id'] as String,
              name: row['name'] as String,
              updatedAt: DateTime.parse(row['updated_at'] as String),
            ))
        .toList();
  }

  Future<IdCardTemplateDetail> fetchTemplate(String id) async {
    final row = await _client
        .from('id_card_templates')
        .select('id, name, front_layout, back_layout')
        .eq('id', id)
        .single();
    return _detailFromRow(row);
  }

  Future<String> createTemplate(String name) async {
    final row = await _client
        .from('id_card_templates')
        .insert({'name': name})
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> updateTemplateLayouts({
    required String id,
    required List<IdCardTemplateElement> frontLayout,
    required List<IdCardTemplateElement> backLayout,
  }) async {
    await _client.from('id_card_templates').update({
      'front_layout': frontLayout.map((e) => e.toJson()).toList(),
      'back_layout': backLayout.map((e) => e.toJson()).toList(),
    }).eq('id', id);
  }

  Future<void> renameTemplate({
    required String id,
    required String name,
  }) async {
    await _client
        .from('id_card_templates')
        .update({'name': name}).eq('id', id);
  }

  Future<void> deleteTemplate(String id) async {
    await _client.from('id_card_templates').delete().eq('id', id);
  }

  /// Uploads a static image (e.g. a school logo) for an `image`-type
  /// element and returns its Storage object path. Not tied to a
  /// particular template row — the same uploaded image can be reused by
  /// any element in any template.
  Future<String> uploadTemplateImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final path = '${DateTime.now().microsecondsSinceEpoch}_$fileName';
    await _client.storage.from(_templateImagesBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }

  /// Resolves [imagePath] to a time-limited signed URL, or null if
  /// [imagePath] is null — mirrors StudentsRepository.fetchStudentPhotoUrl.
  Future<String?> fetchTemplateImageUrl(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return null;
    return _client.storage
        .from(_templateImagesBucket)
        .createSignedUrl(imagePath, 3600);
  }

  IdCardTemplateDetail _detailFromRow(Map<String, dynamic> row) {
    final frontRaw = row['front_layout'] as List? ?? const [];
    final backRaw = row['back_layout'] as List? ?? const [];
    return IdCardTemplateDetail(
      id: row['id'] as String,
      name: row['name'] as String,
      frontLayout: frontRaw
          .map((e) =>
              IdCardTemplateElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      backLayout: backRaw
          .map((e) =>
              IdCardTemplateElement.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
```

- [ ] **Step 6: Write the signature-guard test**

```dart
// test/id_card_templates_repository_test.dart
import 'package:capstone_dashboard/data/id_card_templates_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
      'IdCardTemplatesRepository methods have the expected signatures',
      () {
    final client = SupabaseClient('https://example.supabase.co', 'anon-key');
    final repo = IdCardTemplatesRepository(client);

    Future<List<IdCardTemplateSummary>> Function() fetchTemplates =
        repo.fetchTemplates;
    Future<IdCardTemplateDetail> Function(String) fetchTemplate =
        repo.fetchTemplate;
    Future<String> Function(String) createTemplate = repo.createTemplate;
    Future<void> Function({
      required String id,
      required List<IdCardTemplateElement> frontLayout,
      required List<IdCardTemplateElement> backLayout,
    }) updateTemplateLayouts = repo.updateTemplateLayouts;
    Future<void> Function({required String id, required String name})
        renameTemplate = repo.renameTemplate;
    Future<void> Function(String) deleteTemplate = repo.deleteTemplate;
    Future<String> Function({
      required Uint8List bytes,
      required String fileName,
    }) uploadTemplateImage = repo.uploadTemplateImage;
    Future<String?> Function(String?) fetchTemplateImageUrl =
        repo.fetchTemplateImageUrl;

    expect(fetchTemplates, isNotNull);
    expect(fetchTemplate, isNotNull);
    expect(createTemplate, isNotNull);
    expect(updateTemplateLayouts, isNotNull);
    expect(renameTemplate, isNotNull);
    expect(deleteTemplate, isNotNull);
    expect(uploadTemplateImage, isNotNull);
    expect(fetchTemplateImageUrl, isNotNull);
  });
}
```

Add `import 'dart:typed_data';` at the top of this test file for `Uint8List`.

- [ ] **Step 7: Run the full suite and analyze**

Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.
Run: `flutter analyze lib/data/id_card_templates_repository.dart packages/rfid_management_module/lib/id_card_template.dart` — expect no issues.

- [ ] **Step 8: Commit**

```bash
git add packages/rfid_management_module/lib/id_card_template.dart packages/rfid_management_module/lib/rfid_management_module.dart packages/rfid_management_module/test/id_card_template_test.dart lib/data/id_card_templates_repository.dart test/id_card_templates_repository_test.dart
git commit -m "feat: add id card template model and IdCardTemplatesRepository"
```

---

### Task 3: `guardian_contact_no` + signature storage — repository, model, and registration form

**Files:**
- Modify: `lib/data/students_repository.dart`
- Modify: `lib/models/student_record.dart`
- Modify: `packages/rfid_management_module/lib/rfid_student_row.dart`
- Modify: `packages/rfid_management_module/lib/ui/student_records_tab.dart`
- Modify: `lib/ui/it_technician_connected_page.dart`
- Test: `test/students_repository_id_card_test.dart`

**Interfaces:**
- Consumes: Task 1's `students.guardian_contact_no`/`students.signature_path` columns and `student-signatures` bucket.
- Produces: `StudentsRepository.uploadStudentSignature({studentId, bytes})`/`fetchStudentSignatureUrl(signaturePath)`, `StudentsRepository.create`/`update` both gaining a required `guardianContactNo` param, `StudentRecord.guardianContactNo`/`signaturePath`, `RfidStudentRow.guardianContactNo`, `RfidRegistrationForm.guardianContactNo` — consumed by Task 9's print flow (the `guardianContactNo`/`signaturePath` values an `idData`/`signature` element resolves to at print time).

**Context:** Read `lib/data/students_repository.dart` in full first, especially `_selectEmbed` (around line 45-70), `create` (line 324), `update` (line 390), and `uploadStudentPhoto`/`fetchStudentPhotoUrl` (line 439-461) — this brief's line numbers may drift if the file changed since this brief was written; confirm by reading before editing. The new signature methods mirror the existing photo methods exactly.

**Important — do NOT touch `guardianName`.** This codebase's existing `guardianName` (on `StudentRecord`/`RfidStudentRow`) is derived from a `parent_student_links` join, not a plain column, and the registration form's existing "Parent/Guardian Name" field is never actually persisted anywhere today (a pre-existing, unrelated gap — `_saveStudent`'s `repo.update`/`repo.create` calls don't forward `form.guardianName` to any column). This task adds a NEW, separate `guardianContactNo` field that IS fully wired end-to-end; it does not fix or touch the existing `guardianName` gap. Per this plan's Global Constraints, fixing that is explicitly out of scope.

- [ ] **Step 1: Extend `_selectEmbed` and add `guardianContactNo` to `create`/`update`**

In `_selectEmbed`, add two lines right after `photo_path,`:
```
guardian_contact_no,
signature_path,
```

In `create`, add `required String guardianContactNo,` right after `required String sectionName,` (before the optional `email`/`phoneNumber` params), and add this line to the `students` insert map, right after `'section_id': sectionId,`:
```dart
      'guardian_contact_no':
          guardianContactNo.trim().isEmpty ? null : guardianContactNo.trim(),
```

In `update`, add `required String guardianContactNo,` right after `required String sectionName,`, and add the same line to the `students` update map, right after `'section_id': sectionId,`.

- [ ] **Step 2: Add signature upload/fetch methods**

Add immediately after `fetchStudentPhotoUrl` (before `_fetchById`):

```dart
  static const _signatureBucket = 'student-signatures';

  /// Uploads a freshly-captured signature and records its path on the
  /// student's row — mirrors [uploadStudentPhoto] exactly, backing the
  /// Print ID flow's signature-capture step.
  Future<String> uploadStudentSignature({
    required String studentId,
    required Uint8List bytes,
  }) async {
    final path = '$studentId.png';
    await _client.storage.from(_signatureBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true,
          ),
        );
    await _client
        .from('students')
        .update({'signature_path': path}).eq('id', studentId);
    return path;
  }

  /// Resolves [signaturePath] to a time-limited signed URL, or null if
  /// [signaturePath] is null — mirrors [fetchStudentPhotoUrl] exactly.
  Future<String?> fetchStudentSignatureUrl(String? signaturePath) async {
    if (signaturePath == null || signaturePath.isEmpty) return null;
    return _client.storage
        .from(_signatureBucket)
        .createSignedUrl(signaturePath, 3600);
  }
```

- [ ] **Step 3: Add the new fields to `StudentRecord`**

In the constructor, add `required this.guardianContactNo,` right after `required this.guardianName,`, and add `this.signaturePath,` right after `this.photoPath,`.

Add the fields:
```dart
  final String guardianContactNo;

  /// `students.signature_path` — the Storage object path (not a URL,
  /// since the bucket is private) of this student's captured signature,
  /// if one's been captured.
  final String? signaturePath;
```

In `fromSupabase`, add to the returned `StudentRecord(...)`, right after `guardianName: guardian,`:
```dart
      guardianContactNo: (row['guardian_contact_no'] as String?)?.trim() ?? '',
      signaturePath: row['signature_path'] as String?,
```

- [ ] **Step 4: Add the new fields to `RfidStudentRow`/`RfidRegistrationForm`**

In `RfidStudentRow`'s constructor, add `required this.guardianContactNo,` right after `required this.guardianName,`. Add the field `final String guardianContactNo;` right after `final String guardianName;`.

In `RfidRegistrationForm`'s constructor, add `required this.guardianContactNo,` right after `required this.guardianName,`. Add the field `final String guardianContactNo;` right after `final String guardianName;`.

- [ ] **Step 5: Add the registration form field**

Read `packages/rfid_management_module/lib/ui/student_records_tab.dart` in full first — specifically `_guardianController` (around line 573-574), its `dispose()` entry (around line 595), `_save()`'s `RfidRegistrationForm(...)` construction (around line 619-629), and the "Parent/Guardian Name" field in `build()` (around line 745-751) — this brief's line numbers may drift; confirm by reading before editing.

Add a controller right after `_guardianController`:
```dart
  late final _guardianContactNoController =
      TextEditingController(text: widget.editing?.guardianContactNo ?? '');
```

Add its disposal right after `_guardianController.dispose();`:
```dart
    _guardianContactNoController.dispose();
```

In `_save()`'s `RfidRegistrationForm(...)` construction, add right after `guardianName: _guardianController.text.trim(),`:
```dart
          guardianContactNo: _guardianContactNoController.text.trim(),
```

In `build()`, add right after the "Parent/Guardian Name" `TextField` block (after its closing `),` at line 751, before the `],` that closes `children`):
```dart
          const SizedBox(height: 14),
          const FieldLabel('Guardian Contact No.'),
          TextField(
            controller: _guardianContactNoController,
            enabled: !_saving,
            style: fieldTextStyle(context),
            decoration: fieldDecoration(context),
          ),
```

- [ ] **Step 6: Wire `guardianContactNo` into `ItTechnicianConnectedPage`**

Read `lib/ui/it_technician_connected_page.dart` in full first — specifically the `RfidStudentRow` mapping inside `_studentRows` (around line 190-198) and `_saveStudent`'s `repo.update`/`repo.create` calls (around line 253-267) — this brief's line numbers may drift; confirm by reading before editing.

In the `RfidStudentRow(...)` mapping, add right after `guardianName: s.guardianName,`:
```dart
            guardianContactNo: s.guardianContactNo,
```

In `_saveStudent`, add `guardianContactNo: form.guardianContactNo,` to BOTH the `repo.update(...)` call (`editing != null` branch) and the `repo.create(...)` call (`else` branch), in each case right after `sectionName: form.section,`.

- [ ] **Step 7: Write the signature-guard test**

```dart
// test/students_repository_id_card_test.dart
import 'dart:typed_data';

import 'package:capstone_dashboard/data/students_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
      'uploadStudentSignature and fetchStudentSignatureUrl have the '
      'expected signatures', () {
    final client = SupabaseClient('https://example.supabase.co', 'anon-key');
    final repo = StudentsRepository(client);

    Future<String> Function({
      required String studentId,
      required Uint8List bytes,
    }) uploadStudentSignature = repo.uploadStudentSignature;
    Future<String?> Function(String?) fetchStudentSignatureUrl =
        repo.fetchStudentSignatureUrl;

    expect(uploadStudentSignature, isNotNull);
    expect(fetchStudentSignatureUrl, isNotNull);
  });

  test('create and update accept guardianContactNo', () {
    final client = SupabaseClient('https://example.supabase.co', 'anon-key');
    final repo = StudentsRepository(client);

    Future<StudentRecord> Function({
      required String studentNumber,
      required String rfidUid,
      required String firstName,
      required String middleInitial,
      required String lastName,
      required String course,
      required int yearLevel,
      required String sectionName,
      required String guardianContactNo,
      String? email,
      String? phoneNumber,
    }) create = repo.create;
    Future<StudentRecord> Function({
      required String id,
      required String studentNumber,
      required String rfidUid,
      required String firstName,
      required String middleInitial,
      required String lastName,
      required String course,
      required int yearLevel,
      required String sectionName,
      required String guardianContactNo,
    }) update = repo.update;

    expect(create, isNotNull);
    expect(update, isNotNull);
  });
}
```

Check `StudentsRepository`'s actual current import — `StudentRecord` may already be re-exported from `students_repository.dart` itself (check `import`/`export` lines at the top of that file first) rather than needing a separate `package:capstone_dashboard/models/student_record.dart` import; adjust the test's imports to match whatever the real file does.

- [ ] **Step 8: Run the full suite and analyze**

Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.
Run: `flutter analyze lib/data/students_repository.dart lib/models/student_record.dart lib/ui/it_technician_connected_page.dart packages/rfid_management_module/lib/rfid_student_row.dart packages/rfid_management_module/lib/ui/student_records_tab.dart` — expect no issues.

- [ ] **Step 9: Commit**

```bash
git add lib/data/students_repository.dart lib/models/student_record.dart lib/ui/it_technician_connected_page.dart packages/rfid_management_module/lib/rfid_student_row.dart packages/rfid_management_module/lib/ui/student_records_tab.dart test/students_repository_id_card_test.dart
git commit -m "feat: add guardian contact no. and signature storage to StudentsRepository"
```

---

### Task 4: "ID Templates" tab + template list screen + editor page stub

**Files:**
- Create: `packages/rfid_management_module/lib/ui/id_card_template_list_view.dart`
- Create: `packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart`
- Modify: `packages/rfid_management_module/lib/ui/it_technician_dashboard_page.dart`
- Modify: `packages/rfid_management_module/lib/rfid_management_module.dart`
- Modify: `packages/rfid_management_module/test/it_technician_dashboard_tab_wiring_test.dart`
- Modify: `lib/ui/it_technician_connected_page.dart`

**Interfaces:**
- Consumes: Task 2's `IdCardTemplatesRepository`/`IdCardTemplateSummary`/`IdCardTemplateDetail`/`IdCardTemplateElement`.
- Produces: `IdCardTemplateSummaryRow{id, name, updatedAtLabel}`, `IdCardTemplateListView` widget, `ItTechnicianDashboardTab.idTemplates` (new enum value), `ItTechnicianDashboardPage.idTemplatesTabBuilder` (new required `WidgetBuilder`). **`IdCardTemplateEditorPage`'s constructor shape is FIXED as of this task** — `{templateName, initialFrontLayout, initialBackLayout, onSave}` — Tasks 5, 6, and 7 only ever change what's inside its `build()`/state, never these four constructor parameters (Task 7 is the one exception: it adds a fifth parameter, `onUploadImage` — see that task).

**Context:** This task establishes the SAME "ship a real, minimal placeholder now; a later task fills in the real content" pattern already used successfully for `RfidRequestsTab` in the RFID assignment requests feature: `IdCardTemplateEditorPage` here is a real, working, navigable page (not a TODO) — Task 5 replaces its body with the actual canvas editor. Read `packages/rfid_management_module/lib/ui/it_technician_dashboard_page.dart` in full first, especially the `enum ItTechnicianDashboardTab` (line 16), the constructor's `required this.rfidRequestsTabBuilder,` (around line 81), `_buildTabContent`'s switch, and `_SubNavBar._tabs` — this brief's line numbers may drift; confirm by reading before editing.

- [ ] **Step 1: Write `IdCardTemplateListView`**

```dart
// packages/rfid_management_module/lib/ui/id_card_template_list_view.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'it_technician_dashboard_page.dart' show ItTechnicianColors;

class IdCardTemplateSummaryRow {
  const IdCardTemplateSummaryRow({
    required this.id,
    required this.name,
    required this.updatedAtLabel,
  });

  final String id;
  final String name;
  final String updatedAtLabel;
}

/// Lists saved ID card templates — create, open (into the editor),
/// rename, delete. Read-only summary rows; the actual layout is only
/// loaded once the editor opens a specific template (see
/// IdCardTemplateEditorPage).
class IdCardTemplateListView extends StatelessWidget {
  const IdCardTemplateListView({
    super.key,
    required this.templates,
    required this.isLoading,
    required this.onCreate,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final List<IdCardTemplateSummaryRow> templates;
  final bool isLoading;
  final VoidCallback onCreate;
  final ValueChanged<String> onOpen;
  final void Function(String id, String currentName) onRename;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ItTechnicianColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ItTechnicianColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ID Card Templates',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ItTechnicianColors.rowText(context),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Template'),
                style: FilledButton.styleFrom(
                  backgroundColor: ItTechnicianColors.azureBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (templates.isEmpty)
            Text(
              'No templates yet — create one to design your first ID card.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: ItTechnicianColors.mutedText(context),
              ),
            )
          else
            for (final template in templates)
              _TemplateRow(
                template: template,
                onOpen: () => onOpen(template.id),
                onRename: () => onRename(template.id, template.name),
                onDelete: () => onDelete(template.id),
              ),
        ],
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    required this.template,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final IdCardTemplateSummaryRow template;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ItTechnicianColors.rowText(context),
                    ),
                  ),
                  Text(
                    'Updated ${template.updatedAtLabel}',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: ItTechnicianColors.mutedText(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Rename',
            onPressed: onRename,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 18, color: ItTechnicianColors.dangerRed),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Write the `IdCardTemplateEditorPage` stub**

```dart
// packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart
import 'package:flutter/material.dart';

import '../id_card_template.dart';

/// Full-screen ID card template editor. This task ships a minimal
/// placeholder body — Task 5 replaces this file's state/build with the
/// real canvas/toolbox/properties-panel editor. The constructor's shape
/// is fixed as of this task: later tasks only change what's inside
/// build()/state (Task 7 adds one more constructor parameter,
/// `onUploadImage` — see that task).
class IdCardTemplateEditorPage extends StatefulWidget {
  const IdCardTemplateEditorPage({
    super.key,
    required this.templateName,
    required this.initialFrontLayout,
    required this.initialBackLayout,
    required this.onSave,
  });

  final String templateName;
  final List<IdCardTemplateElement> initialFrontLayout;
  final List<IdCardTemplateElement> initialBackLayout;

  /// Persists both sides' current element lists. Rethrows on failure so
  /// this page can show the error inline.
  final Future<void> Function(
    List<IdCardTemplateElement> frontLayout,
    List<IdCardTemplateElement> backLayout,
  ) onSave;

  @override
  State<IdCardTemplateEditorPage> createState() =>
      _IdCardTemplateEditorPageState();
}

class _IdCardTemplateEditorPageState extends State<IdCardTemplateEditorPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Editing ${widget.templateName}')),
      body: const Center(child: Text('Template editor coming soon.')),
    );
  }
}
```

- [ ] **Step 3: Add the 5th tab to `ItTechnicianDashboardPage`**

In `enum ItTechnicianDashboardTab`, add `idTemplates`:
```dart
enum ItTechnicianDashboardTab { studentRecords, readerDevices, technicalIssues, rfidRequests, idTemplates }
```

In `ItTechnicianDashboardPage`'s constructor, add `required this.idTemplatesTabBuilder,` alongside `required this.rfidRequestsTabBuilder,`, and the field:
```dart
  final WidgetBuilder idTemplatesTabBuilder;
```

In `_buildTabContent`'s switch, add a case:
```dart
      case ItTechnicianDashboardTab.idTemplates:
        return widget.idTemplatesTabBuilder(context);
```

In `_SubNavBar._tabs`, add an entry:
```dart
    (
      ItTechnicianDashboardTab.idTemplates,
      'ID Templates',
      Icons.badge_outlined,
    ),
```

No `ItTechnicianOverviewStats` change — no Overview stat card for this tab.

- [ ] **Step 4: Export the new files and update the wiring test**

Add to `packages/rfid_management_module/lib/rfid_management_module.dart`:
```dart
export 'ui/id_card_template_editor_page.dart';
export 'ui/id_card_template_list_view.dart';
```
(Alphabetical position among the other `ui/` exports — check the file's current ordering first.)

Read `packages/rfid_management_module/test/it_technician_dashboard_tab_wiring_test.dart` in full first — it constructs `ItTechnicianDashboardPage` twice. Add `idTemplatesTabBuilder: (_) => const Center(child: Text('ID Templates Content')),` to BOTH construction sites, matching the existing stub-builder style used for the other tab builders in each.

- [ ] **Step 5: Wire `ItTechnicianConnectedPage`**

Read `lib/ui/it_technician_connected_page.dart` in full first.

Add the import: `import '../data/id_card_templates_repository.dart';`.

Add a `IdCardTemplatesRepository? get _idCardTemplatesRepo` getter, matching every other repo getter's exact shape:
```dart
  IdCardTemplatesRepository? get _idCardTemplatesRepo =>
      AppEnv.supabaseConfigured
          ? IdCardTemplatesRepository(Supabase.instance.client)
          : null;
```

Add fields:
```dart
  List<IdCardTemplateSummary>? _idCardTemplates;
  bool _idCardTemplatesLoading = false;
```

Add `_loadIdCardTemplates()`:
```dart
  Future<void> _loadIdCardTemplates() async {
    final repo = _idCardTemplatesRepo;
    if (repo == null) return;
    setState(() => _idCardTemplatesLoading = true);
    try {
      final templates = await repo.fetchTemplates();
      if (!mounted) return;
      setState(() => _idCardTemplates = templates);
    } catch (e) {
      _toast('Could not load templates: $e');
    } finally {
      if (mounted) setState(() => _idCardTemplatesLoading = false);
    }
  }
```

Add `_createIdCardTemplate()`, `_openIdCardTemplateEditor()`, `_renameIdCardTemplate()`, `_deleteIdCardTemplate()`, and a small date formatter:
```dart
  Future<void> _createIdCardTemplate() async {
    final repo = _idCardTemplatesRepo;
    if (repo == null) return;
    try {
      final id = await repo.createTemplate('Untitled Template');
      await _loadIdCardTemplates();
      await _openIdCardTemplateEditor(id);
    } catch (e) {
      _toast('Could not create template: $e');
    }
  }

  Future<void> _openIdCardTemplateEditor(String templateId) async {
    final repo = _idCardTemplatesRepo;
    if (repo == null || !mounted) return;
    IdCardTemplateDetail detail;
    try {
      detail = await repo.fetchTemplate(templateId);
    } catch (e) {
      _toast('Could not open template: $e');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IdCardTemplateEditorPage(
          templateName: detail.name,
          initialFrontLayout: detail.frontLayout,
          initialBackLayout: detail.backLayout,
          onSave: (front, back) => repo.updateTemplateLayouts(
            id: templateId,
            frontLayout: front,
            backLayout: back,
          ),
        ),
      ),
    );
    await _loadIdCardTemplates();
  }

  Future<void> _renameIdCardTemplate(String id, String currentName) async {
    final repo = _idCardTemplatesRepo;
    if (repo == null) return;
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename Template'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty) return;
    try {
      await repo.renameTemplate(id: id, name: newName);
      await _loadIdCardTemplates();
    } catch (e) {
      _toast('Could not rename template: $e');
    }
  }

  Future<void> _deleteIdCardTemplate(String id) async {
    final repo = _idCardTemplatesRepo;
    if (repo == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Template'),
        content: const Text('This cannot be undone. Delete this template?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style:
                FilledButton.styleFrom(backgroundColor: ItTechnicianColors.dangerRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repo.deleteTemplate(id);
      await _loadIdCardTemplates();
    } catch (e) {
      _toast('Could not delete template: $e');
    }
  }

  String _formatTemplateDate(DateTime date) =>
      '${date.month}/${date.day}/${date.year}';
```

Add `_loadIdCardTemplates()` to `initState`'s existing sequence of `WidgetsBinding.instance.addPostFrameCallback((_) => ...)` calls.

In the `build` method's `ItTechnicianDashboardPage(...)` construction, add:
```dart
      idTemplatesTabBuilder: (_) => IdCardTemplateListView(
        templates: (_idCardTemplates ?? const [])
            .map((t) => IdCardTemplateSummaryRow(
                  id: t.id,
                  name: t.name,
                  updatedAtLabel: _formatTemplateDate(t.updatedAt),
                ))
            .toList(),
        isLoading: _idCardTemplatesLoading,
        onCreate: _createIdCardTemplate,
        onOpen: _openIdCardTemplateEditor,
        onRename: _renameIdCardTemplate,
        onDelete: _deleteIdCardTemplate,
      ),
```

- [ ] **Step 6: Run the full suite and analyze**

Run: `flutter test packages/rfid_management_module/test/it_technician_dashboard_tab_wiring_test.dart` (from the worktree root — do NOT `cd` into the package first).
Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.
Run: `flutter analyze packages/rfid_management_module lib/ui/it_technician_connected_page.dart` — expect no issues.

- [ ] **Step 7: Commit**

```bash
git add packages/rfid_management_module/lib/ui/id_card_template_list_view.dart packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart packages/rfid_management_module/lib/ui/it_technician_dashboard_page.dart packages/rfid_management_module/lib/rfid_management_module.dart packages/rfid_management_module/test/it_technician_dashboard_tab_wiring_test.dart lib/ui/it_technician_connected_page.dart
git commit -m "feat: add ID Templates tab, template list screen, and editor page stub"
```

---

### Task 5: Editor foundation — canvas, toolbox, select/move/resize/delete, save

**Files:**
- Modify: `packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart`
- Test: `packages/rfid_management_module/test/id_card_template_editor_page_test.dart`

**Interfaces:**
- Consumes: Task 4's fixed `IdCardTemplateEditorPage` constructor contract; Task 2's `IdCardTemplateElement`/`IdCardElementType`/`idCardWidthPt`/`idCardHeightPt`.
- Produces: the real editor body — `Set<String> _selectedIds` selection model (used as-is by Task 6's multi-select additions and Task 7's properties-panel additions), `_addElement`, `_moveSelection`, `_resizeElement`, `_deleteSelectedElements`, `_setCurrentElements`, `_save` — Task 6 and Task 7 both modify this same file, calling these same method names.

**Context:** This task replaces the Task 4 stub's body entirely. Selection is a `Set<String>` from the start (not a nullable single ID) even though this task only ever puts 0 or 1 element in it — this avoids Task 6's multi-select work requiring a structural rewrite of this task's selection logic. The on-screen canvas applies a fixed zoom to `idCardWidthPt`/`idCardHeightPt` for comfortable editing; every element's stored `x`/`y`/`width`/`height` stays in real points regardless of zoom (per this plan's Global Constraints).

- [ ] **Step 1: Replace the editor page's state with the real editor**

Replace the entire content of `packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart` with:

```dart
// packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart
import 'package:flutter/material.dart';

import '../id_card_template.dart';
import 'it_technician_dashboard_page.dart' show ItTechnicianColors;

/// Full-screen ID card template editor — toolbox (drag elements onto the
/// canvas), canvas (front/back toggle above it), properties panel. The
/// constructor's shape is fixed as of Task 4: later tasks only change
/// what's inside build()/state (Task 7 adds one more constructor
/// parameter, `onUploadImage`).
class IdCardTemplateEditorPage extends StatefulWidget {
  const IdCardTemplateEditorPage({
    super.key,
    required this.templateName,
    required this.initialFrontLayout,
    required this.initialBackLayout,
    required this.onSave,
  });

  final String templateName;
  final List<IdCardTemplateElement> initialFrontLayout;
  final List<IdCardTemplateElement> initialBackLayout;

  final Future<void> Function(
    List<IdCardTemplateElement> frontLayout,
    List<IdCardTemplateElement> backLayout,
  ) onSave;

  @override
  State<IdCardTemplateEditorPage> createState() =>
      _IdCardTemplateEditorPageState();
}

class _IdCardTemplateEditorPageState extends State<IdCardTemplateEditorPage> {
  static const double _zoom = 3.0;
  static const List<(IdCardElementType, String, IconData)> _toolboxItems = [
    (IdCardElementType.staticText, 'Text', Icons.text_fields),
    (IdCardElementType.image, 'Image', Icons.image_outlined),
    (IdCardElementType.idData, 'ID Data', Icons.badge_outlined),
    (IdCardElementType.idPicture, 'ID Picture', Icons.account_box_outlined),
    (IdCardElementType.signature, 'Signature', Icons.draw_outlined),
    (IdCardElementType.rectangle, 'Rectangle', Icons.crop_square),
    (IdCardElementType.roundedRect, 'RoundedRect', Icons.rounded_corner),
    (IdCardElementType.ellipse, 'Ellipse', Icons.circle_outlined),
    (IdCardElementType.line, 'Line', Icons.horizontal_rule),
  ];

  late List<IdCardTemplateElement> _frontElements =
      List.of(widget.initialFrontLayout);
  late List<IdCardTemplateElement> _backElements =
      List.of(widget.initialBackLayout);
  bool _showingFront = true;
  Set<String> _selectedIds = {};
  bool _saving = false;
  bool _dirty = false;
  int _idCounter = 0;

  List<IdCardTemplateElement> get _currentElements =>
      _showingFront ? _frontElements : _backElements;

  void _setCurrentElements(List<IdCardTemplateElement> elements) {
    setState(() {
      if (_showingFront) {
        _frontElements = elements;
      } else {
        _backElements = elements;
      }
      _dirty = true;
    });
  }

  String _nextElementId() {
    _idCounter += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_idCounter';
  }

  IdCardTemplateElement _defaultElementFor(
    IdCardElementType type,
    String id,
  ) {
    const defaultWidth = 80.0;
    const defaultHeight = 20.0;
    switch (type) {
      case IdCardElementType.staticText:
        return IdCardTemplateElement(
          id: id,
          type: type,
          x: 10,
          y: 10,
          width: defaultWidth,
          height: defaultHeight,
          textContent: 'Static Text',
          fontFamily: 'Poppins',
          fontSize: 10,
          color: 0xFF000000,
          textAlign: 'left',
        );
      case IdCardElementType.idData:
        return IdCardTemplateElement(
          id: id,
          type: type,
          x: 10,
          y: 10,
          width: defaultWidth,
          height: defaultHeight,
          fieldKey: IdDataFieldKey.firstName,
          fontFamily: 'Poppins',
          fontSize: 10,
          color: 0xFF000000,
          textAlign: 'left',
        );
      case IdCardElementType.image:
        return IdCardTemplateElement(
            id: id, type: type, x: 10, y: 10, width: 60, height: 60);
      case IdCardElementType.idPicture:
        return IdCardTemplateElement(
            id: id, type: type, x: 10, y: 10, width: 60, height: 70);
      case IdCardElementType.signature:
        return IdCardTemplateElement(
            id: id, type: type, x: 10, y: 10, width: 100, height: 30);
      case IdCardElementType.rectangle:
        return IdCardTemplateElement(
          id: id,
          type: type,
          x: 10,
          y: 10,
          width: 100,
          height: 40,
          fillColor: 0x00000000,
          strokeColor: 0xFF000000,
          strokeWidth: 1,
        );
      case IdCardElementType.roundedRect:
        return IdCardTemplateElement(
          id: id,
          type: type,
          x: 10,
          y: 10,
          width: 100,
          height: 40,
          fillColor: 0x00000000,
          strokeColor: 0xFF000000,
          strokeWidth: 1,
          cornerRadius: 8,
        );
      case IdCardElementType.ellipse:
        return IdCardTemplateElement(
          id: id,
          type: type,
          x: 10,
          y: 10,
          width: 40,
          height: 40,
          fillColor: 0x00000000,
          strokeColor: 0xFF000000,
          strokeWidth: 1,
        );
      case IdCardElementType.line:
        return IdCardTemplateElement(
          id: id,
          type: type,
          x: 10,
          y: 10,
          width: 80,
          height: 1,
          strokeColor: 0xFF000000,
          strokeWidth: 1,
        );
    }
  }

  void _addElement(IdCardElementType type) {
    final id = _nextElementId();
    _setCurrentElements([..._currentElements, _defaultElementFor(type, id)]);
    setState(() => _selectedIds = {id});
  }

  void _selectOnly(String id) => setState(() => _selectedIds = {id});

  void _moveSelection(Offset screenDelta) {
    final deltaX = screenDelta.dx / _zoom;
    final deltaY = screenDelta.dy / _zoom;
    final elements = _currentElements.map((e) {
      if (!_selectedIds.contains(e.id)) return e;
      return e.copyWith(
        x: (e.x + deltaX).clamp(0, idCardWidthPt - e.width),
        y: (e.y + deltaY).clamp(0, idCardHeightPt - e.height),
      );
    }).toList();
    _setCurrentElements(elements);
  }

  void _resizeElement(String id, Offset screenDelta) {
    final deltaX = screenDelta.dx / _zoom;
    final deltaY = screenDelta.dy / _zoom;
    final elements = _currentElements.map((e) {
      if (e.id != id) return e;
      return e.copyWith(
        width: (e.width + deltaX).clamp(8, idCardWidthPt - e.x),
        height: (e.height + deltaY).clamp(8, idCardHeightPt - e.y),
      );
    }).toList();
    _setCurrentElements(elements);
  }

  void _deleteSelectedElements() {
    if (_selectedIds.isEmpty) return;
    _setCurrentElements(
      _currentElements.where((e) => !_selectedIds.contains(e.id)).toList(),
    );
    setState(() => _selectedIds = {});
  }

  void _updateSelected(
    IdCardTemplateElement Function(IdCardTemplateElement) update,
  ) {
    if (_selectedIds.length != 1) return;
    final id = _selectedIds.first;
    final elements =
        _currentElements.map((e) => e.id == id ? update(e) : e).toList();
    _setCurrentElements(elements);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_frontElements, _backElements);
      if (mounted) setState(() => _dirty = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
          'You have unsaved changes to this template. Leave without saving?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscardIfDirty() && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Editing ${widget.templateName}'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _saving
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : FilledButton(
                      onPressed: _dirty ? _save : null,
                      child: const Text('Save'),
                    ),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Front'),
                    selected: _showingFront,
                    onSelected: (_) => setState(() {
                      _showingFront = true;
                      _selectedIds = {};
                    }),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Back'),
                    selected: !_showingFront,
                    onSelected: (_) => setState(() {
                      _showingFront = false;
                      _selectedIds = {};
                    }),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildToolbox(context),
                  Expanded(child: _buildCanvasArea(context)),
                  _buildPropertiesPanel(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbox(BuildContext context) {
    return SizedBox(
      width: 110,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final (type, label, icon) in _toolboxItems)
            Draggable<IdCardElementType>(
              data: type,
              feedback: Material(
                color: Colors.transparent,
                child: Icon(icon, size: 28, color: ItTechnicianColors.azureBlue),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Icon(icon, size: 22),
                    const SizedBox(height: 4),
                    Text(label,
                        style: const TextStyle(fontSize: 10),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCanvasArea(BuildContext context) {
    return DragTarget<IdCardElementType>(
      onAcceptWithDetails: (details) => _addElement(details.data),
      builder: (context, candidateData, rejectedData) => Center(
        child: Container(
          width: idCardWidthPt * _zoom,
          height: idCardHeightPt * _zoom,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: ItTechnicianColors.cardBorder(context)),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _selectedIds = {}),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final element in _currentElements)
                  _buildElementWidget(element),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildElementWidget(IdCardTemplateElement element) {
    final isSelected = _selectedIds.contains(element.id);
    return Positioned(
      left: element.x * _zoom,
      top: element.y * _zoom,
      width: element.width * _zoom,
      height: element.height * _zoom,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectOnly(element.id),
        onPanStart: (_) {
          if (!_selectedIds.contains(element.id)) _selectOnly(element.id);
        },
        onPanUpdate: (details) => _moveSelection(details.delta),
        child: Container(
          decoration: isSelected
              ? BoxDecoration(
                  border: Border.all(
                      color: ItTechnicianColors.azureBlue, width: 2))
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: _elementContent(element)),
              if (isSelected && _selectedIds.length == 1)
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: GestureDetector(
                    onPanUpdate: (details) =>
                        _resizeElement(element.id, details.delta),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: ItTechnicianColors.azureBlue,
                        border: Border.all(color: Colors.white, width: 1.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _elementContent(IdCardTemplateElement element) {
    switch (element.type) {
      case IdCardElementType.staticText:
        return Text(
          element.textContent ?? '',
          style: TextStyle(
            fontSize: (element.fontSize ?? 10) * _zoom / 2,
            color: Color(element.color ?? 0xFF000000),
          ),
        );
      case IdCardElementType.idData:
        return Text(
          '{${element.fieldKey?.name ?? 'field'}}',
          style: TextStyle(
            fontSize: (element.fontSize ?? 10) * _zoom / 2,
            color: Color(element.color ?? 0xFF000000),
            fontStyle: FontStyle.italic,
          ),
        );
      case IdCardElementType.image:
        return Container(
          color: const Color(0xFFE5E7EB),
          alignment: Alignment.center,
          child: const Icon(Icons.image_outlined, size: 16),
        );
      case IdCardElementType.idPicture:
        return Container(
          color: const Color(0xFFE5E7EB),
          alignment: Alignment.center,
          child: const Text('PHOTO', style: TextStyle(fontSize: 9)),
        );
      case IdCardElementType.signature:
        return Container(
          color: const Color(0xFFF3F4F6),
          alignment: Alignment.center,
          child: const Text('SIGNATURE', style: TextStyle(fontSize: 8)),
        );
      case IdCardElementType.rectangle:
        return Container(
          decoration: BoxDecoration(
            color: Color(element.fillColor ?? 0x00000000),
            border: Border.all(
              color: Color(element.strokeColor ?? 0xFF000000),
              width: element.strokeWidth ?? 1,
            ),
          ),
        );
      case IdCardElementType.roundedRect:
        return Container(
          decoration: BoxDecoration(
            color: Color(element.fillColor ?? 0x00000000),
            border: Border.all(
              color: Color(element.strokeColor ?? 0xFF000000),
              width: element.strokeWidth ?? 1,
            ),
            borderRadius:
                BorderRadius.circular((element.cornerRadius ?? 0) * _zoom),
          ),
        );
      case IdCardElementType.ellipse:
        return Container(
          decoration: BoxDecoration(
            color: Color(element.fillColor ?? 0x00000000),
            border: Border.all(
              color: Color(element.strokeColor ?? 0xFF000000),
              width: element.strokeWidth ?? 1,
            ),
            shape: BoxShape.circle,
          ),
        );
      case IdCardElementType.line:
        return Container(color: Color(element.strokeColor ?? 0xFF000000));
    }
  }

  Widget _buildPropertiesPanel(BuildContext context) {
    if (_selectedIds.length != 1) {
      return const SizedBox(
        width: 160,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Select an element to edit its properties.',
            style: TextStyle(fontSize: 11),
          ),
        ),
      );
    }
    final id = _selectedIds.first;
    final element = _currentElements.firstWhere((e) => e.id == id);
    return SizedBox(
      width: 160,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Position & Size',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _numberField(
                'X', element.x, (v) => _updateSelected((e) => e.copyWith(x: v))),
            _numberField(
                'Y', element.y, (v) => _updateSelected((e) => e.copyWith(y: v))),
            _numberField('W', element.width,
                (v) => _updateSelected((e) => e.copyWith(width: v))),
            _numberField('H', element.height,
                (v) => _updateSelected((e) => e.copyWith(height: v))),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _deleteSelectedElements,
              child: const Text('Delete Element'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 20, child: Text(label, style: const TextStyle(fontSize: 11))),
          Expanded(
            child: TextFormField(
              key: ValueKey('${_selectedIds.first}_$label'),
              initialValue: value.toStringAsFixed(0),
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              ),
              onFieldSubmitted: (text) {
                final parsed = double.tryParse(text);
                if (parsed != null) onChanged(parsed);
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Write the editor's core-interaction widget test**

```dart
// packages/rfid_management_module/test/id_card_template_editor_page_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

void main() {
  testWidgets('adding a text element from the toolbox shows it on the canvas',
      (tester) async {
    List<IdCardTemplateElement>? savedFront;
    List<IdCardTemplateElement>? savedBack;

    await tester.pumpWidget(MaterialApp(
      home: IdCardTemplateEditorPage(
        templateName: 'Test Template',
        initialFrontLayout: const [],
        initialBackLayout: const [],
        onSave: (front, back) async {
          savedFront = front;
          savedBack = back;
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Editing Test Template'), findsOneWidget);
    expect(find.text('Static Text', skipOffstage: false), findsNothing);

    // Simulate a toolbox drag-and-drop onto the canvas.
    final textTool = find.text('Text');
    final canvas = find.byType(DragTarget<IdCardElementType>);
    await tester.drag(textTool, tester.getCenter(canvas) - tester.getCenter(textTool));
    await tester.pumpAndSettle();

    expect(find.text('Static Text'), findsOneWidget);

    // Save persists the current in-memory layout.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(savedFront, isNotNull);
    expect(savedFront, hasLength(1));
    expect(savedFront!.single.type, IdCardElementType.staticText);
    expect(savedBack, isNotNull);
    expect(savedBack, isEmpty);
  });

  testWidgets('deleting the selected element removes it from the canvas',
      (tester) async {
    const element = IdCardTemplateElement(
      id: 'existing-1',
      type: IdCardElementType.staticText,
      x: 10,
      y: 10,
      width: 80,
      height: 20,
      textContent: 'Existing Text',
    );

    await tester.pumpWidget(MaterialApp(
      home: IdCardTemplateEditorPage(
        templateName: 'Test Template',
        initialFrontLayout: const [element],
        initialBackLayout: const [],
        onSave: (front, back) async {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Existing Text'), findsOneWidget);

    await tester.tap(find.text('Existing Text'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete Element'));
    await tester.pumpAndSettle();

    expect(find.text('Existing Text'), findsNothing);
  });
}
```

- [ ] **Step 3: Run the tests**

Run: `flutter test packages/rfid_management_module/test/id_card_template_editor_page_test.dart` (from the worktree root — do NOT `cd` into the package first).
Expected: 2 tests PASS. If the simulated drag-and-drop in the first test doesn't register (`Draggable`/`DragTarget` gesture simulation can be finicky in `flutter_test`), an acceptable fallback is asserting the toolbox and canvas both render (`find.text('Text')`, `find.byType(DragTarget<IdCardElementType>)`) and separately unit-testing `_defaultElementFor`'s behavior indirectly through the second test's delete flow — but attempt the real drag simulation first; only fall back if it's reliably flaky.

Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.
Run: `flutter analyze packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart` — expect no issues.

- [ ] **Step 4: Commit**

```bash
git add packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart packages/rfid_management_module/test/id_card_template_editor_page_test.dart
git commit -m "feat: add ID card template editor canvas, toolbox, and save"
```

---

### Task 6: Alignment guides, undo/redo, copy/paste, keyboard shortcuts

**Files:**
- Modify: `packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart`
- Test: `packages/rfid_management_module/test/id_card_template_editor_page_test.dart`

**Interfaces:**
- Consumes: Task 5's `_selectedIds`, `_currentElements`, `_setCurrentElements`, `_frontElements`/`_backElements`.
- Produces: `_pushHistory`, `_undo`, `_redo`, `_copySelection`, `_pasteClipboard` — no later task depends on these names, but keep them exactly as written here since this task's own steps below reference them by name.

**Context:** Read the current `packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart` in full first (Task 5's output) — this task adds fields/methods and makes small, targeted edits to existing methods; it does not replace the whole file.

- [ ] **Step 1: Add history and clipboard state**

Add these fields to `_IdCardTemplateEditorPageState`, alongside the existing ones:
```dart
  final List<(List<IdCardTemplateElement>, List<IdCardTemplateElement>)>
      _undoStack = [];
  final List<(List<IdCardTemplateElement>, List<IdCardTemplateElement>)>
      _redoStack = [];
  static const _maxHistory = 50;
  List<IdCardTemplateElement> _clipboard = [];
  List<double> _guideLinesX = [];
  List<double> _guideLinesY = [];
  final _focusNode = FocusNode();
```

Add a `dispose()` override (this class didn't have one before):
```dart
  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }
```

- [ ] **Step 2: Add undo/redo methods**

```dart
  void _pushHistory() {
    _undoStack.add((List.of(_frontElements), List.of(_backElements)));
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add((List.of(_frontElements), List.of(_backElements)));
    final (front, back) = _undoStack.removeLast();
    setState(() {
      _frontElements = front;
      _backElements = back;
      _selectedIds = {};
      _dirty = true;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add((List.of(_frontElements), List.of(_backElements)));
    final (front, back) = _redoStack.removeLast();
    setState(() {
      _frontElements = front;
      _backElements = back;
      _selectedIds = {};
      _dirty = true;
    });
  }
```

- [ ] **Step 3: Push history before each discrete mutating action**

In `_addElement`, add `_pushHistory();` as the very first line of the method body (before `final id = _nextElementId();`).

In `_deleteSelectedElements`, add `_pushHistory();` as the first line inside the `if (_selectedIds.isEmpty) return;` guard's else-path — i.e. right after that guard, before `_setCurrentElements(...)`.

In `_buildElementWidget`'s `onPanStart` callback, add a call to `_pushHistory()` so a move only records ONE history entry per drag, not one per frame. Replace:
```dart
        onPanStart: (_) {
          if (!_selectedIds.contains(element.id)) _selectOnly(element.id);
        },
```
with:
```dart
        onPanStart: (_) {
          if (!_selectedIds.contains(element.id)) _selectOnly(element.id);
          _pushHistory();
        },
```

In the resize handle's `GestureDetector` (inside `_buildElementWidget`), add an `onPanStart` that also pushes history. Replace:
```dart
                  child: GestureDetector(
                    onPanUpdate: (details) =>
                        _resizeElement(element.id, details.delta),
```
with:
```dart
                  child: GestureDetector(
                    onPanStart: (_) => _pushHistory(),
                    onPanUpdate: (details) =>
                        _resizeElement(element.id, details.delta),
```

- [ ] **Step 4: Add copy/paste**

```dart
  void _copySelection() {
    _clipboard =
        _currentElements.where((e) => _selectedIds.contains(e.id)).toList();
  }

  void _pasteClipboard() {
    if (_clipboard.isEmpty) return;
    _pushHistory();
    final pasted = _clipboard
        .map((e) => e.copyWith(
              id: '${_nextElementId()}-paste',
              x: e.x + 10,
              y: e.y + 10,
            ))
        .toList();
    setState(() {
      if (_showingFront) {
        _frontElements = [..._frontElements, ...pasted];
      } else {
        _backElements = [..._backElements, ...pasted];
      }
      _selectedIds = pasted.map((e) => e.id).toSet();
      _dirty = true;
    });
  }
```

- [ ] **Step 5: Add shift-click multi-select**

Replace `_buildElementWidget`'s `onTap` callback. Replace:
```dart
        onTap: () => _selectOnly(element.id),
```
with:
```dart
        onTap: () => _handleElementTap(element.id),
```

Add the new handler (near `_selectOnly`):
```dart
  void _handleElementTap(String id) {
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    setState(() {
      if (isShift) {
        _selectedIds = _selectedIds.contains(id)
            ? ({..._selectedIds}..remove(id))
            : {..._selectedIds, id};
      } else {
        _selectedIds = {id};
      }
    });
  }
```

Add the import: `import 'package:flutter/services.dart';` (for `HardwareKeyboard`/`LogicalKeyboardKey`, used here and in Step 7).

- [ ] **Step 6: Add marquee (drag-select) over empty canvas**

Add fields:
```dart
  Offset? _marqueeStart;
  Offset? _marqueeCurrent;
```

Replace the canvas's background `GestureDetector` in `_buildCanvasArea`. Replace:
```dart
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _selectedIds = {}),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final element in _currentElements)
                  _buildElementWidget(element),
              ],
            ),
          ),
```
with:
```dart
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _selectedIds = {}),
            onPanStart: (details) => setState(() {
              _marqueeStart = details.localPosition;
              _marqueeCurrent = details.localPosition;
            }),
            onPanUpdate: (details) {
              if (_marqueeStart == null) return;
              setState(() => _marqueeCurrent = details.localPosition);
            },
            onPanEnd: (_) {
              final start = _marqueeStart;
              final end = _marqueeCurrent;
              if (start != null && end != null) {
                final rect = Rect.fromPoints(start, end);
                final hits = _currentElements
                    .where((e) => rect.overlaps(Rect.fromLTWH(
                          e.x * _zoom,
                          e.y * _zoom,
                          e.width * _zoom,
                          e.height * _zoom,
                        )))
                    .map((e) => e.id)
                    .toSet();
                setState(() => _selectedIds = hits);
              }
              setState(() {
                _marqueeStart = null;
                _marqueeCurrent = null;
              });
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final element in _currentElements)
                  _buildElementWidget(element),
                for (final x in _guideLinesX)
                  Positioned(
                    left: x,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 1, color: Colors.redAccent),
                  ),
                for (final y in _guideLinesY)
                  Positioned(
                    top: y,
                    left: 0,
                    right: 0,
                    child: Container(height: 1, color: Colors.redAccent),
                  ),
                if (_marqueeStart != null && _marqueeCurrent != null)
                  Positioned.fromRect(
                    rect: Rect.fromPoints(_marqueeStart!, _marqueeCurrent!),
                    child: Container(
                      decoration: BoxDecoration(
                        color: ItTechnicianColors.azureBlue.withOpacity(0.1),
                        border:
                            Border.all(color: ItTechnicianColors.azureBlue),
                      ),
                    ),
                  ),
              ],
            ),
          ),
```

(Note the marquee's `onPanStart`/`onPanUpdate`/`onPanEnd` sit on the CANVAS's background `GestureDetector`, separate from each element's own `onPanStart`/`onPanUpdate` in `_buildElementWidget` — `HitTestBehavior.opaque` plus each element's own `GestureDetector` intercepting its own drags means the background's pan handlers only fire when the drag starts on empty canvas space, not on an element.)

- [ ] **Step 7: Add alignment guides during move**

Replace `_moveSelection` entirely:
```dart
  void _moveSelection(Offset screenDelta) {
    final deltaX = screenDelta.dx / _zoom;
    final deltaY = screenDelta.dy / _zoom;
    const snapThreshold = 4.0;

    final others =
        _currentElements.where((e) => !_selectedIds.contains(e.id)).toList();
    final movingElements =
        _currentElements.where((e) => _selectedIds.contains(e.id)).toList();
    if (movingElements.isEmpty) return;

    var adjustedDeltaX = deltaX;
    var adjustedDeltaY = deltaY;
    final guideX = <double>[];
    final guideY = <double>[];

    for (final moving in movingElements) {
      final newX = moving.x + deltaX;
      final newY = moving.y + deltaY;
      final candidatesX = [
        0.0,
        idCardWidthPt / 2 - moving.width / 2,
        idCardWidthPt - moving.width,
        for (final other in others) other.x,
        for (final other in others) other.x + other.width / 2 - moving.width / 2,
        for (final other in others) other.x + other.width - moving.width,
      ];
      final candidatesY = [
        0.0,
        idCardHeightPt / 2 - moving.height / 2,
        idCardHeightPt - moving.height,
        for (final other in others) other.y,
        for (final other in others) other.y + other.height / 2 - moving.height / 2,
        for (final other in others) other.y + other.height - moving.height,
      ];
      for (final cx in candidatesX) {
        if ((newX - cx).abs() < snapThreshold) {
          adjustedDeltaX = cx - moving.x;
          guideX.add((cx + moving.width / 2) * _zoom);
        }
      }
      for (final cy in candidatesY) {
        if ((newY - cy).abs() < snapThreshold) {
          adjustedDeltaY = cy - moving.y;
          guideY.add((cy + moving.height / 2) * _zoom);
        }
      }
    }

    final elements = _currentElements.map((e) {
      if (!_selectedIds.contains(e.id)) return e;
      return e.copyWith(
        x: (e.x + adjustedDeltaX).clamp(0, idCardWidthPt - e.width),
        y: (e.y + adjustedDeltaY).clamp(0, idCardHeightPt - e.height),
      );
    }).toList();

    setState(() {
      _guideLinesX = guideX;
      _guideLinesY = guideY;
    });
    _setCurrentElements(elements);
  }
```

Clear the guide lines when a drag ends — add `onPanEnd` to each element's `GestureDetector` in `_buildElementWidget`. Replace:
```dart
        onPanUpdate: (details) => _moveSelection(details.delta),
```
with:
```dart
        onPanUpdate: (details) => _moveSelection(details.delta),
        onPanEnd: (_) => setState(() {
          _guideLinesX = [];
          _guideLinesY = [];
        }),
```

- [ ] **Step 8: Wire keyboard shortcuts**

Add the handler method:
```dart
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (isCtrl &&
        HardwareKeyboard.instance.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyZ) {
      _redo();
      return KeyEventResult.handled;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      _undo();
      return KeyEventResult.handled;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      _copySelection();
      return KeyEventResult.handled;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyV) {
      _pasteClipboard();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _deleteSelectedElements();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
```

Wrap the `Scaffold` in `build()` with a `Focus` widget. Replace:
```dart
      child: Scaffold(
```
with:
```dart
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Scaffold(
```
and add the matching closing `)` for the new `Focus(` right after the `Scaffold(...)`'s own closing, before the `PopScope`'s closing — i.e. `Scaffold(...)` becomes `Focus(...child: Scaffold(...))`. Read the current `build()` method's exact bracket structure first and add the closing paren precisely; do not just append text at the end of the file.

- [ ] **Step 9: Write undo/redo and copy/paste tests**

Add to `packages/rfid_management_module/test/id_card_template_editor_page_test.dart`:

```dart
  testWidgets('undo restores the layout after adding an element',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: IdCardTemplateEditorPage(
        templateName: 'Test Template',
        initialFrontLayout: const [],
        initialBackLayout: const [],
        onSave: (front, back) async {},
      ),
    ));
    await tester.pumpAndSettle();

    final textTool = find.text('Text');
    final canvas = find.byType(DragTarget<IdCardElementType>);
    await tester.drag(
        textTool, tester.getCenter(canvas) - tester.getCenter(textTool));
    await tester.pumpAndSettle();
    expect(find.text('Static Text'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Static Text'), findsNothing);
  });

  testWidgets('copy then paste duplicates the selected element',
      (tester) async {
    const element = IdCardTemplateElement(
      id: 'existing-1',
      type: IdCardElementType.staticText,
      x: 10,
      y: 10,
      width: 80,
      height: 20,
      textContent: 'Existing Text',
    );

    await tester.pumpWidget(MaterialApp(
      home: IdCardTemplateEditorPage(
        templateName: 'Test Template',
        initialFrontLayout: const [element],
        initialBackLayout: const [],
        onSave: (front, back) async {},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Existing Text'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Existing Text'), findsNWidgets(2));
  });
```

Add `import 'package:flutter/services.dart';` to this test file's imports for `LogicalKeyboardKey`.

- [ ] **Step 10: Run the tests**

Run: `flutter test packages/rfid_management_module/test/id_card_template_editor_page_test.dart` (from the worktree root).
Expected: 4 tests PASS (the 2 from Task 5 plus these 2). If `sendKeyDownEvent`/`sendKeyEvent` don't register as expected against a `Focus`+`onKeyEvent` widget in this Flutter version, try wrapping the test's `pumpWidget` call's `home` with an explicit `Shortcuts`-free plain `Focus` ancestor request via `tester.binding.focusManager.primaryFocus?.requestFocus()` after the first `pumpAndSettle()`, then retry — but attempt the direct approach above first.

Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.
Run: `flutter analyze packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart` — expect no issues.

- [ ] **Step 11: Commit**

```bash
git add packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart packages/rfid_management_module/test/id_card_template_editor_page_test.dart
git commit -m "feat: add undo/redo, copy/paste, multi-select, and alignment guides to the template editor"
```

---

### Task 7: Properties panel type-specific fields + image upload

**Files:**
- Modify: `packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart`
- Modify: `lib/ui/it_technician_connected_page.dart`
- Test: `packages/rfid_management_module/test/id_card_template_editor_page_test.dart`

**Interfaces:**
- Consumes: Task 2's `IdCardTemplatesRepository.uploadTemplateImage`, Task 5/6's `_buildPropertiesPanel`/`_updateSelected`.
- Produces: `IdCardTemplateEditorPage` gains a FIFTH constructor parameter, `required this.onUploadImage` (`Future<String> Function(Uint8List bytes, String fileName)`) — this is the one exception to Task 4's "constructor is fixed" note. `ItTechnicianConnectedPage`'s existing `_openIdCardTemplateEditor` (Task 4) must supply this new parameter.

**Context:** `file_picker` is already a pubspec dependency (used elsewhere in this app) — check `pubspec.yaml`'s root `dependencies:` to confirm the exact package name/version already pinned, and reuse it as-is; do not add a new image-picking dependency.

- [ ] **Step 1: Add the `onUploadImage` constructor parameter**

In `IdCardTemplateEditorPage`'s constructor, add `required this.onUploadImage,` after `required this.onSave,`. Add the field:
```dart
  /// Uploads a static image (e.g. a school logo) for an Image-type
  /// element and returns its Storage object path. This page has no
  /// Supabase access of its own.
  final Future<String> Function(Uint8List bytes, String fileName) onUploadImage;
```
Add `import 'dart:typed_data';` to this file's imports.

- [ ] **Step 2: Add color presets and a swatch row helper**

```dart
  static const _colorPresets = [
    0xFF000000,
    0xFFFFFFFF,
    0xFF345892,
    0xFFCD4855,
    0xFF137333,
    0xFFF5C518,
  ];

  Widget _colorSwatchRow(int? current, ValueChanged<int> onPick) {
    return Wrap(
      spacing: 6,
      children: [
        for (final c in _colorPresets)
          GestureDetector(
            onTap: () => onPick(c),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      current == c ? ItTechnicianColors.azureBlue : Colors.grey,
                  width: current == c ? 2 : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
```

- [ ] **Step 3: Extend the properties panel with type-specific fields**

Replace `_buildPropertiesPanel`'s body from `const SizedBox(height: 12),` (right after the four `_numberField` calls) through the closing of the `Column`'s `children` list — i.e. insert the type-specific block BETWEEN the position/size fields and the "Delete Element" button. Replace:
```dart
            _numberField('H', element.height,
                (v) => _updateSelected((e) => e.copyWith(height: v))),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _deleteSelectedElements,
              child: const Text('Delete Element'),
            ),
```
with:
```dart
            _numberField('H', element.height,
                (v) => _updateSelected((e) => e.copyWith(height: v))),
            const SizedBox(height: 12),
            ..._typeSpecificFields(element),
            OutlinedButton(
              onPressed: _deleteSelectedElements,
              child: const Text('Delete Element'),
            ),
```

Add `_typeSpecificFields`:
```dart
  List<Widget> _typeSpecificFields(IdCardTemplateElement element) {
    switch (element.type) {
      case IdCardElementType.staticText:
        return [
          const Text('Content', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          TextFormField(
            key: ValueKey('${element.id}_content'),
            initialValue: element.textContent ?? '',
            style: const TextStyle(fontSize: 11),
            onFieldSubmitted: (text) =>
                _updateSelected((e) => e.copyWith(textContent: text)),
          ),
          const SizedBox(height: 8),
          const Text('Font Size', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          _numberField(
            'Size',
            element.fontSize ?? 10,
            (v) => _updateSelected((e) => e.copyWith(fontSize: v)),
          ),
          const Text('Color', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          _colorSwatchRow(
            element.color,
            (c) => _updateSelected((e) => e.copyWith(color: c)),
          ),
          const SizedBox(height: 12),
        ];
      case IdCardElementType.idData:
        return [
          const Text('Field', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          DropdownButton<IdDataFieldKey>(
            value: element.fieldKey ?? IdDataFieldKey.firstName,
            isExpanded: true,
            items: [
              for (final key in IdDataFieldKey.values)
                DropdownMenuItem(value: key, child: Text(key.name, style: const TextStyle(fontSize: 11))),
            ],
            onChanged: (key) {
              if (key != null) _updateSelected((e) => e.copyWith(fieldKey: key));
            },
          ),
          const SizedBox(height: 8),
          const Text('Font Size', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          _numberField(
            'Size',
            element.fontSize ?? 10,
            (v) => _updateSelected((e) => e.copyWith(fontSize: v)),
          ),
          const Text('Color', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          _colorSwatchRow(
            element.color,
            (c) => _updateSelected((e) => e.copyWith(color: c)),
          ),
          const SizedBox(height: 12),
        ];
      case IdCardElementType.image:
        return [
          OutlinedButton(
            onPressed: () => _pickAndUploadImage(element.id),
            child: const Text('Replace Image'),
          ),
          const SizedBox(height: 12),
        ];
      case IdCardElementType.idPicture:
      case IdCardElementType.signature:
        return const [];
      case IdCardElementType.rectangle:
      case IdCardElementType.roundedRect:
      case IdCardElementType.ellipse:
        return [
          const Text('Fill', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          _colorSwatchRow(
            element.fillColor,
            (c) => _updateSelected((e) => e.copyWith(fillColor: c)),
          ),
          const SizedBox(height: 8),
          const Text('Stroke', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          _colorSwatchRow(
            element.strokeColor,
            (c) => _updateSelected((e) => e.copyWith(strokeColor: c)),
          ),
          const SizedBox(height: 8),
          _numberField(
            'Width',
            element.strokeWidth ?? 1,
            (v) => _updateSelected((e) => e.copyWith(strokeWidth: v)),
          ),
          if (element.type == IdCardElementType.roundedRect)
            _numberField(
              'Radius',
              element.cornerRadius ?? 0,
              (v) => _updateSelected((e) => e.copyWith(cornerRadius: v)),
            ),
          const SizedBox(height: 12),
        ];
      case IdCardElementType.line:
        return [
          const Text('Stroke', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          _colorSwatchRow(
            element.strokeColor,
            (c) => _updateSelected((e) => e.copyWith(strokeColor: c)),
          ),
          const SizedBox(height: 8),
          _numberField(
            'Width',
            element.strokeWidth ?? 1,
            (v) => _updateSelected((e) => e.copyWith(strokeWidth: v)),
          ),
          const SizedBox(height: 12),
        ];
    }
  }
```

- [ ] **Step 4: Wire image upload**

Add `import 'package:file_picker/file_picker.dart';` to the editor page's imports (check `pubspec.yaml`'s exact package name first, per this task's Context note).

```dart
  Future<void> _pickAndUploadImage(String elementId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (bytes == null) return;
    try {
      final path = await widget.onUploadImage(bytes, file!.name);
      _pushHistory();
      _updateSelected((e) => e.copyWith(imagePath: path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not upload image: $e')));
      }
    }
  }
```

- [ ] **Step 5: Wire `onUploadImage` from `ItTechnicianConnectedPage`**

In `_openIdCardTemplateEditor` (Task 4), add `onUploadImage:` to the `IdCardTemplateEditorPage(...)` construction, right after `onSave: (front, back) => repo.updateTemplateLayouts(...),`:
```dart
          onUploadImage: (bytes, fileName) =>
              repo.uploadTemplateImage(bytes: bytes, fileName: fileName),
```

- [ ] **Step 6: Update the existing widget tests' constructions**

`packages/rfid_management_module/test/id_card_template_editor_page_test.dart` now has 3 `IdCardTemplateEditorPage(...)` construction sites (from Tasks 5 and 6). Add `onUploadImage: (bytes, fileName) async => 'fake/path.png',` to EVERY one of them.

- [ ] **Step 7: Write a properties-panel field test**

Add to `packages/rfid_management_module/test/id_card_template_editor_page_test.dart`:

```dart
  testWidgets('editing a static text element\'s content updates the canvas',
      (tester) async {
    const element = IdCardTemplateElement(
      id: 'existing-1',
      type: IdCardElementType.staticText,
      x: 10,
      y: 10,
      width: 80,
      height: 20,
      textContent: 'Original',
    );

    await tester.pumpWidget(MaterialApp(
      home: IdCardTemplateEditorPage(
        templateName: 'Test Template',
        initialFrontLayout: const [element],
        initialBackLayout: const [],
        onSave: (front, back) async {},
        onUploadImage: (bytes, fileName) async => 'fake/path.png',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Updated');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Updated'), findsOneWidget);
    expect(find.text('Original'), findsNothing);
  });
```

- [ ] **Step 8: Run the tests**

Run: `flutter test packages/rfid_management_module/test/id_card_template_editor_page_test.dart` (from the worktree root).
Expected: 5 tests PASS.
Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.
Run: `flutter analyze packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart lib/ui/it_technician_connected_page.dart` — expect no issues.

- [ ] **Step 9: Commit**

```bash
git add packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart lib/ui/it_technician_connected_page.dart packages/rfid_management_module/test/id_card_template_editor_page_test.dart
git commit -m "feat: add properties panel type-specific fields and image upload"
```

---

### Task 8: Signature capture dialog

**Files:**
- Modify: `packages/rfid_management_module/pubspec.yaml`
- Create: `packages/rfid_management_module/lib/ui/signature_capture_dialog.dart`
- Modify: `packages/rfid_management_module/lib/rfid_management_module.dart`
- Test: `packages/rfid_management_module/test/signature_capture_dialog_test.dart`

**Interfaces:**
- Consumes: nothing from other tasks in this plan.
- Produces: `SignatureCaptureDialog` widget, popping with `Uint8List?` (captured PNG bytes, or null if cancelled) — consumed by Task 9's print flow.

**Context:** This dialog structurally mirrors the existing `WebcamCaptureDialog` (`packages/rfid_management_module/lib/ui/webcam_capture_dialog.dart` — read it in full first) exactly: Clear/Retake, "Use Signature"/"Done" buttons, same `Dialog`/sizing/typography conventions. It draws with mouse/touch/stylus rather than streaming a camera, using the `signature` package — a pure-Dart Flutter drawing-canvas widget with no native code, so it needs no platform-specific companion package (unlike `camera`/`camera_windows`) and works identically on web and Windows.

- [ ] **Step 1: Add the `signature` dependency**

Add to `packages/rfid_management_module/pubspec.yaml`'s `dependencies:`, alongside `camera: ^0.11.0+2`:
```yaml
  signature: ^5.5.0
```
Run `flutter pub get` from the worktree root. If `^5.5.0` doesn't resolve (a newer or older major may be current by the time this task runs), use the latest available 5.x release instead — check `flutter pub outdated` or pub.dev for the current version and adjust the constraint accordingly; this package has no bearing on any other part of this app, so any reasonably current 5.x release is fine.

- [ ] **Step 2: Write the dialog**

```dart
// packages/rfid_management_module/lib/ui/signature_capture_dialog.dart
import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:signature/signature.dart';

import 'it_technician_dashboard_page.dart' show ItTechnicianColors;

/// Full-screen signature capture — draws with mouse/touch/stylus rather
/// than streaming a camera, but otherwise structurally mirrors
/// [WebcamCaptureDialog] exactly (Clear/Retake, "Use Signature" button).
/// Pops with the captured PNG bytes, or `null` if closed without
/// capturing anything.
class SignatureCaptureDialog extends StatefulWidget {
  const SignatureCaptureDialog({super.key});

  @override
  State<SignatureCaptureDialog> createState() =>
      _SignatureCaptureDialogState();
}

class _SignatureCaptureDialogState extends State<SignatureCaptureDialog> {
  final _controller = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  Uint8List? _capturedBytes;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_controller.isEmpty) {
      setState(() => _error = 'Draw a signature before continuing.');
      return;
    }
    try {
      final bytes = await _controller.toPngBytes();
      if (bytes == null) {
        setState(() => _error = 'Could not capture the signature.');
        return;
      }
      setState(() {
        _capturedBytes = bytes;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not capture the signature: $e');
    }
  }

  void _retake() {
    _controller.clear();
    setState(() => _capturedBytes = null);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 480,
        height: 420,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Capture Signature',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: ItTechnicianColors.rowText(context),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildBody(context)),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: ItTechnicianColors.dangerRed,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_capturedBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(_capturedBytes!, fit: BoxFit.contain),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: Colors.white,
        child: Signature(controller: _controller, backgroundColor: Colors.white),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    if (_capturedBytes != null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(onPressed: _retake, child: const Text('Retake')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_capturedBytes),
              style: FilledButton.styleFrom(backgroundColor: ItTechnicianColors.azureBlue),
              child: const Text('Use Signature'),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(
            onPressed: () => _controller.clear(),
            child: const Text('Clear'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: _capture,
            style: FilledButton.styleFrom(backgroundColor: ItTechnicianColors.azureBlue),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Export it from the package barrel**

Add to `packages/rfid_management_module/lib/rfid_management_module.dart`:
```dart
export 'ui/signature_capture_dialog.dart';
```

- [ ] **Step 4: Write a widget test**

```dart
// packages/rfid_management_module/test/signature_capture_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

void main() {
  testWidgets('shows an error when Done is tapped with nothing drawn',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SignatureCaptureDialog()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    expect(find.text('Draw a signature before continuing.'), findsOneWidget);
  });

  testWidgets('Cancel pops with null', (tester) async {
    Uint8List? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showDialog<Uint8List>(
              context: context,
              builder: (_) => const SignatureCaptureDialog(),
            );
          },
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
```

Add `import 'dart:typed_data';` to this test file's imports.

- [ ] **Step 5: Run the tests**

Run: `flutter test packages/rfid_management_module/test/signature_capture_dialog_test.dart` (from the worktree root).
Expected: 2 tests PASS.
Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.
Run: `flutter analyze packages/rfid_management_module/lib/ui/signature_capture_dialog.dart` — expect no issues.

- [ ] **Step 6: Commit**

```bash
git add packages/rfid_management_module/pubspec.yaml packages/rfid_management_module/pubspec.lock packages/rfid_management_module/lib/ui/signature_capture_dialog.dart packages/rfid_management_module/lib/rfid_management_module.dart packages/rfid_management_module/test/signature_capture_dialog_test.dart
git commit -m "feat: add signature capture dialog"
```

(Only `git add` `pubspec.lock` if `flutter pub get` actually regenerated it — check `git status` first.)

---

### Task 9: Print flow integration + renderer replacement

**Files:**
- Modify: `lib/documents/student_id_card_pdf.dart`
- Modify: `packages/rfid_management_module/lib/ui/id_card_print_dialog.dart`
- Modify: `lib/ui/it_technician_connected_page.dart`

**Interfaces:**
- Consumes: Task 2's `IdCardTemplateElement`/`IdCardElementType`/`IdDataFieldKey`/`idCardWidthPt`/`idCardHeightPt`/`IdCardTemplateSummary`/`IdCardTemplateDetail`/`IdCardTemplatesRepository`, Task 3's `guardianContactNo`/`signaturePath`/`uploadStudentSignature`/`fetchStudentSignatureUrl`, Task 8's `SignatureCaptureDialog`.
- Produces: `buildIdCardPdf`, `printIdCard`, `IdCardPrintData` in `lib/documents/student_id_card_pdf.dart` (this file's ONLY exports after this task — `StudentIdCardData`/`buildStudentIdCardPdf`/`printStudentIdCard` are removed entirely, not deprecated alongside). No later task in this plan depends on this task's produced names.

**Context:** Read `lib/documents/student_id_card_pdf.dart`, `packages/rfid_management_module/lib/ui/id_card_print_dialog.dart`, and `lib/ui/it_technician_connected_page.dart`'s `_handlePrintId`/`_printStudentId` (around line 202-245) in full first — this brief's line numbers may drift; confirm by reading before editing. This task replaces the hardcoded single-layout renderer with one that reads ANY saved template's element list, and extends the print dialog with a template picker and a conditional signature-capture step.

- [ ] **Step 1: Replace the renderer**

Replace the entire content of `lib/documents/student_id_card_pdf.dart` with:

```dart
// lib/documents/student_id_card_pdf.dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// CR-80 card size (3.375in x 2.125in — standard ID/credit card),
/// landscape. Matches [idCardWidthPt]/[idCardHeightPt] exactly — the same
/// canonical point space every IdCardTemplateElement's x/y/width/height
/// is stored in, so this renderer needs no unit conversion beyond
/// wrapping in a PdfPageFormat.
final _cardFormat = PdfPageFormat(idCardWidthPt, idCardHeightPt, marginAll: 0);

/// The real, per-student values an `idData` element's [IdDataFieldKey]
/// resolves to at print time.
class IdCardPrintData {
  const IdCardPrintData({
    required this.firstName,
    required this.middleInitial,
    required this.lastName,
    required this.studentNumber,
    required this.course,
    required this.section,
    required this.yearLevel,
    required this.guardianName,
    required this.guardianContactNo,
    required this.photoBytes,
    this.signatureBytes,
  });

  final String firstName;
  final String middleInitial;
  final String lastName;
  final String studentNumber;
  final String course;
  final String section;
  final String yearLevel;
  final String guardianName;
  final String guardianContactNo;
  final Uint8List photoBytes;

  /// Null when the student hasn't had a signature captured yet — a
  /// `signature`-type element then renders as a blank box.
  final Uint8List? signatureBytes;

  String valueFor(IdDataFieldKey key) {
    switch (key) {
      case IdDataFieldKey.firstName:
        return firstName;
      case IdDataFieldKey.middleInitial:
        return middleInitial;
      case IdDataFieldKey.lastName:
        return lastName;
      case IdDataFieldKey.studentNumber:
        return studentNumber;
      case IdDataFieldKey.course:
        return course;
      case IdDataFieldKey.section:
        return section;
      case IdDataFieldKey.yearLevel:
        return yearLevel;
      case IdDataFieldKey.guardianName:
        return guardianName;
      case IdDataFieldKey.guardianContactNo:
        return guardianContactNo;
    }
  }
}

pw.Widget _renderElement(
  IdCardTemplateElement element,
  IdCardPrintData data,
  Map<String, Uint8List> imageBytesByPath,
) {
  switch (element.type) {
    case IdCardElementType.staticText:
      return pw.Text(
        element.textContent ?? '',
        style: pw.TextStyle(fontSize: element.fontSize ?? 10),
      );
    case IdCardElementType.idData:
      final key = element.fieldKey;
      return pw.Text(
        key == null ? '' : data.valueFor(key),
        style: pw.TextStyle(fontSize: element.fontSize ?? 10),
      );
    case IdCardElementType.image:
      final bytes =
          element.imagePath == null ? null : imageBytesByPath[element.imagePath];
      if (bytes == null) return pw.SizedBox();
      return pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain);
    case IdCardElementType.idPicture:
      return pw.Image(pw.MemoryImage(data.photoBytes), fit: pw.BoxFit.cover);
    case IdCardElementType.signature:
      final bytes = data.signatureBytes;
      if (bytes == null) return pw.SizedBox();
      return pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain);
    case IdCardElementType.rectangle:
    case IdCardElementType.roundedRect:
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: element.fillColor == null
              ? null
              : PdfColor.fromInt(element.fillColor!),
          border: element.strokeColor == null
              ? null
              : pw.Border.all(
                  color: PdfColor.fromInt(element.strokeColor!),
                  width: element.strokeWidth ?? 1,
                ),
          borderRadius: element.type == IdCardElementType.roundedRect
              ? pw.BorderRadius.circular(element.cornerRadius ?? 0)
              : null,
        ),
      );
    case IdCardElementType.ellipse:
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: element.fillColor == null
              ? null
              : PdfColor.fromInt(element.fillColor!),
          border: element.strokeColor == null
              ? null
              : pw.Border.all(
                  color: PdfColor.fromInt(element.strokeColor!),
                  width: element.strokeWidth ?? 1,
                ),
          shape: pw.BoxShape.circle,
        ),
      );
    case IdCardElementType.line:
      return pw.Container(
        color:
            element.strokeColor == null ? null : PdfColor.fromInt(element.strokeColor!),
      );
  }
}

pw.Widget _buildSide(
  List<IdCardTemplateElement> elements,
  IdCardPrintData data,
  Map<String, Uint8List> imageBytesByPath,
) {
  return pw.Stack(
    children: [
      for (final element in elements)
        pw.Positioned(
          left: element.x,
          top: element.y,
          child: pw.SizedBox(
            width: element.width,
            height: element.height,
            child: _renderElement(element, data, imageBytesByPath),
          ),
        ),
    ],
  );
}

/// Renders [frontLayout]/[backLayout] (a template's two element lists —
/// see [IdCardTemplateElement]) with [data]'s real per-student values
/// into a two-page PDF (front, then back), ready for print or preview.
/// [imageBytesByPath] supplies the already-downloaded bytes for every
/// `image`-type element's `imagePath` — this renderer does no network
/// fetching of its own.
Future<Uint8List> buildIdCardPdf({
  required List<IdCardTemplateElement> frontLayout,
  required List<IdCardTemplateElement> backLayout,
  required IdCardPrintData data,
  Map<String, Uint8List> imageBytesByPath = const {},
}) async {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: _cardFormat,
      build: (context) => _buildSide(frontLayout, data, imageBytesByPath),
    ),
  );
  doc.addPage(
    pw.Page(
      pageFormat: _cardFormat,
      build: (context) => _buildSide(backLayout, data, imageBytesByPath),
    ),
  );
  return doc.save();
}

/// Opens the OS print dialog for the rendered card — unlike the kiosk's
/// silent receipt printing, an IT Technician needs to consciously
/// pick/confirm the Fargo card printer (a specialized printer among
/// whatever else is installed), so this always shows the dialog rather
/// than printing straight to the default printer.
Future<void> printIdCard({
  required List<IdCardTemplateElement> frontLayout,
  required List<IdCardTemplateElement> backLayout,
  required IdCardPrintData data,
  required String studentName,
  Map<String, Uint8List> imageBytesByPath = const {},
}) async {
  final bytes = await buildIdCardPdf(
    frontLayout: frontLayout,
    backLayout: backLayout,
    data: data,
    imageBytesByPath: imageBytesByPath,
  );
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: 'Student ID - $studentName',
    format: _cardFormat,
  );
}
```

- [ ] **Step 2: Replace `IdCardPrintDialog`**

Replace the entire content of `packages/rfid_management_module/lib/ui/id_card_print_dialog.dart` with:

```dart
// packages/rfid_management_module/lib/ui/id_card_print_dialog.dart
import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';

import '../id_card_template.dart';
import '../rfid_student_row.dart';
import 'it_technician_dashboard_page.dart' show ItTechnicianColors;
import 'signature_capture_dialog.dart';
import 'webcam_capture_dialog.dart';

/// Review-and-print screen for a student ID card — picks a saved
/// template, shows whatever photo is currently on file (if any), lets
/// the IT Technician (re)capture one via the webcam, captures a
/// signature when the chosen template's back layout calls for one, and
/// prints once everything required is in hand. Uploading the
/// photo/signature and actually sending the card to the printer both
/// happen in [onPrint], which the host app supplies (this package has no
/// Supabase/printer access of its own).
class IdCardPrintDialog extends StatefulWidget {
  const IdCardPrintDialog({
    super.key,
    required this.student,
    required this.initialPhotoBytes,
    required this.templates,
    required this.onLoadTemplate,
    required this.onPrint,
  });

  final RfidStudentRow student;

  /// The student's existing photo, downloaded by the host app before
  /// opening this dialog — null when they don't have one on file yet.
  final Uint8List? initialPhotoBytes;

  /// Saved templates, most-recently-updated first (see
  /// IdCardTemplatesRepository.fetchTemplates) — the picker defaults to
  /// the first entry.
  final List<IdCardTemplateSummary> templates;

  /// Fetches a template's full front/back layout when the picker
  /// selection changes — this dialog has no Supabase access of its own.
  final Future<IdCardTemplateDetail> Function(String templateId) onLoadTemplate;

  /// Uploads whatever changed (photo, and signature if captured) and
  /// sends the card to the printer. Rethrows on failure so this dialog
  /// can show the error inline.
  final Future<void> Function({
    required Uint8List photoBytes,
    required Uint8List? signatureBytes,
    required IdCardTemplateDetail template,
  }) onPrint;

  @override
  State<IdCardPrintDialog> createState() => _IdCardPrintDialogState();
}

class _IdCardPrintDialogState extends State<IdCardPrintDialog> {
  late Uint8List? _photoBytes = widget.initialPhotoBytes;
  Uint8List? _signatureBytes;
  IdCardTemplateDetail? _selectedTemplate;
  String? _selectedTemplateId;
  bool _loadingTemplate = false;
  bool _printing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.templates.isNotEmpty) {
      _selectedTemplateId = widget.templates.first.id;
      _loadTemplate(widget.templates.first.id);
    }
  }

  Future<void> _loadTemplate(String id) async {
    setState(() => _loadingTemplate = true);
    try {
      final detail = await widget.onLoadTemplate(id);
      if (mounted) setState(() => _selectedTemplate = detail);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load template: $e');
    } finally {
      if (mounted) setState(() => _loadingTemplate = false);
    }
  }

  bool get _needsSignature => (_selectedTemplate?.backLayout ?? const [])
      .any((e) => e.type == IdCardElementType.signature);

  Future<void> _capturePhoto() async {
    final bytes = await showDialog<Uint8List>(
      context: context,
      builder: (_) => const WebcamCaptureDialog(),
    );
    if (bytes != null && mounted) setState(() => _photoBytes = bytes);
  }

  Future<void> _captureSignature() async {
    final bytes = await showDialog<Uint8List>(
      context: context,
      builder: (_) => const SignatureCaptureDialog(),
    );
    if (bytes != null && mounted) setState(() => _signatureBytes = bytes);
  }

  Future<void> _handlePrint() async {
    final photoBytes = _photoBytes;
    final template = _selectedTemplate;
    if (photoBytes == null || template == null) return;
    if (_needsSignature && _signatureBytes == null) {
      setState(() => _error = 'Capture a signature before printing.');
      return;
    }
    setState(() {
      _printing = true;
      _error = null;
    });
    try {
      await widget.onPrint(
        photoBytes: photoBytes,
        signatureBytes: _signatureBytes,
        template: template,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  bool get _canPrint =>
      !_printing &&
      _photoBytes != null &&
      _selectedTemplate != null &&
      (!_needsSignature || _signatureBytes != null);

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Print Student ID',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: ItTechnicianColors.rowText(context),
                ),
              ),
              const SizedBox(height: 12),
              if (widget.templates.isEmpty)
                Text(
                  'No templates available — create one in the ID Templates tab first.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: ItTechnicianColors.dangerRed,
                  ),
                )
              else
                DropdownButton<String>(
                  value: _selectedTemplateId,
                  isExpanded: true,
                  items: [
                    for (final t in widget.templates)
                      DropdownMenuItem(value: t.id, child: Text(t.name)),
                  ],
                  onChanged: (id) {
                    if (id == null) return;
                    setState(() {
                      _selectedTemplateId = id;
                      _signatureBytes = null;
                    });
                    _loadTemplate(id);
                  },
                ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 100,
                      height: 100,
                      child: _photoBytes == null
                          ? Container(
                              color: ItTechnicianColors.background(context),
                              child: Icon(
                                Icons.person_outline,
                                size: 42,
                                color: ItTechnicianColors.mutedText(context),
                              ),
                            )
                          : Image.memory(_photoBytes!, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.fullName,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: ItTechnicianColors.rowText(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          student.studentNumber,
                          style: GoogleFonts.poppins(
                            fontSize: context.isMobileWidth ? 10 : 12,
                            color: ItTechnicianColors.mutedText(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _printing ? null : _capturePhoto,
                          icon: const Icon(Icons.camera_alt_outlined, size: 16),
                          label: Text(_photoBytes == null ? 'Capture Photo' : 'Retake'),
                        ),
                        if (_needsSignature) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _printing ? null : _captureSignature,
                            icon: const Icon(Icons.draw_outlined, size: 16),
                            label: Text(_signatureBytes == null
                                ? 'Capture Signature'
                                : 'Retake Signature'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (_selectedTemplate != null && _photoBytes != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: PdfPreview(
                    key: ValueKey(
                      '${_selectedTemplateId}_${_photoBytes.hashCode}_${_signatureBytes.hashCode}',
                    ),
                    build: (format) => _buildPreviewBytes(),
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    allowPrinting: false,
                    allowSharing: false,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: ItTechnicianColors.dangerRed)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _printing ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _canPrint ? _handlePrint : null,
                      icon: _printing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.print_outlined, size: 18),
                      label: const Text('Print'),
                      style: FilledButton.styleFrom(backgroundColor: ItTechnicianColors.azureBlue),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _buildPreviewBytes() async {
    final template = _selectedTemplate;
    final photoBytes = _photoBytes;
    if (template == null || photoBytes == null) {
      throw StateError('Preview requested before a template/photo were ready.');
    }
    return _buildPreviewPdf(
      frontLayout: template.frontLayout,
      backLayout: template.backLayout,
      photoBytes: photoBytes,
      signatureBytes: _signatureBytes,
      student: widget.student,
    );
  }
}
```

Note: `_buildPreviewPdf` is a small module-level helper this file needs — since `IdCardPrintDialog` (in `packages/rfid_management_module`) cannot import `lib/documents/student_id_card_pdf.dart`'s `buildIdCardPdf`/`IdCardPrintData` (one-way package dependency: the root app may import this package, never the reverse), the PREVIEW builds its PDF using only types already reachable from this package, resolving `idData` text directly from the `RfidStudentRow` it already has. This duplicates `lib/documents/student_id_card_pdf.dart`'s render shape in miniature — an accepted, deliberate exception to DRY, since the alternative (making the root-app renderer reachable from this package) would invert the codebase's established one-way package dependency direction.

Add `package:pdf` to `packages/rfid_management_module/pubspec.yaml`'s dependencies if it isn't already there (check first — `printing` is already a dependency there, since this file's `PdfPreview` import needs it, but `pdf` itself may not be).

Add these imports to the top of `packages/rfid_management_module/lib/ui/id_card_print_dialog.dart`:
```dart
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
```

Add this private helper at the bottom of the same file, after the `_IdCardPrintDialogState` class:

```dart
String _previewValueFor(IdDataFieldKey key, RfidStudentRow student) {
  switch (key) {
    case IdDataFieldKey.firstName:
      return student.firstName;
    case IdDataFieldKey.middleInitial:
      return student.middleInitial;
    case IdDataFieldKey.lastName:
      return student.lastName;
    case IdDataFieldKey.studentNumber:
      return student.studentNumber;
    case IdDataFieldKey.course:
      return student.course;
    case IdDataFieldKey.section:
      return student.section;
    case IdDataFieldKey.yearLevel:
      return student.yearLevel;
    case IdDataFieldKey.guardianName:
      return student.guardianName;
    case IdDataFieldKey.guardianContactNo:
      return student.guardianContactNo;
  }
}

pw.Widget _renderPreviewElement(
  IdCardTemplateElement element,
  RfidStudentRow student,
  Uint8List photoBytes,
  Uint8List? signatureBytes,
) {
  switch (element.type) {
    case IdCardElementType.staticText:
      return pw.Text(
        element.textContent ?? '',
        style: pw.TextStyle(fontSize: element.fontSize ?? 10),
      );
    case IdCardElementType.idData:
      final key = element.fieldKey;
      return pw.Text(
        key == null ? '' : _previewValueFor(key, student),
        style: pw.TextStyle(fontSize: element.fontSize ?? 10),
      );
    case IdCardElementType.image:
      // Static template images aren't fetched for this in-dialog preview
      // (it has no Supabase access) — the real printed card, built by
      // lib/documents's buildIdCardPdf, does render them.
      return pw.SizedBox();
    case IdCardElementType.idPicture:
      return pw.Image(pw.MemoryImage(photoBytes), fit: pw.BoxFit.cover);
    case IdCardElementType.signature:
      if (signatureBytes == null) return pw.SizedBox();
      return pw.Image(pw.MemoryImage(signatureBytes), fit: pw.BoxFit.contain);
    case IdCardElementType.rectangle:
    case IdCardElementType.roundedRect:
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: element.fillColor == null
              ? null
              : PdfColor.fromInt(element.fillColor!),
          border: element.strokeColor == null
              ? null
              : pw.Border.all(
                  color: PdfColor.fromInt(element.strokeColor!),
                  width: element.strokeWidth ?? 1,
                ),
          borderRadius: element.type == IdCardElementType.roundedRect
              ? pw.BorderRadius.circular(element.cornerRadius ?? 0)
              : null,
        ),
      );
    case IdCardElementType.ellipse:
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: element.fillColor == null
              ? null
              : PdfColor.fromInt(element.fillColor!),
          border: element.strokeColor == null
              ? null
              : pw.Border.all(
                  color: PdfColor.fromInt(element.strokeColor!),
                  width: element.strokeWidth ?? 1,
                ),
          shape: pw.BoxShape.circle,
        ),
      );
    case IdCardElementType.line:
      return pw.Container(
        color: element.strokeColor == null
            ? null
            : PdfColor.fromInt(element.strokeColor!),
      );
  }
}

pw.Widget _buildPreviewSide(
  List<IdCardTemplateElement> elements,
  RfidStudentRow student,
  Uint8List photoBytes,
  Uint8List? signatureBytes,
) {
  return pw.Stack(
    children: [
      for (final element in elements)
        pw.Positioned(
          left: element.x,
          top: element.y,
          child: pw.SizedBox(
            width: element.width,
            height: element.height,
            child: _renderPreviewElement(
                element, student, photoBytes, signatureBytes),
          ),
        ),
    ],
  );
}

Future<Uint8List> _buildPreviewPdf({
  required List<IdCardTemplateElement> frontLayout,
  required List<IdCardTemplateElement> backLayout,
  required Uint8List photoBytes,
  required Uint8List? signatureBytes,
  required RfidStudentRow student,
}) async {
  final format = PdfPageFormat(idCardWidthPt, idCardHeightPt, marginAll: 0);
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: format,
      build: (context) =>
          _buildPreviewSide(frontLayout, student, photoBytes, signatureBytes),
    ),
  );
  doc.addPage(
    pw.Page(
      pageFormat: format,
      build: (context) =>
          _buildPreviewSide(backLayout, student, photoBytes, signatureBytes),
    ),
  );
  return doc.save();
}
```

- [ ] **Step 3: Wire the print flow in `ItTechnicianConnectedPage`**

Replace `_handlePrintId` and `_printStudentId` entirely:

```dart
  Future<void> _handlePrintId(RfidStudentRow student) async {
    final repo = _studentsRepo;
    final templatesRepo = _idCardTemplatesRepo;
    if (repo == null || templatesRepo == null) return;

    Uint8List? existingPhoto;
    try {
      final url = await repo.fetchStudentPhotoUrl(student.photoPath);
      if (url != null) {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) existingPhoto = response.bodyBytes;
      }
    } catch (e) {
      debugPrint('Could not load existing student photo: $e');
    }

    List<IdCardTemplateSummary> templates;
    try {
      templates = await templatesRepo.fetchTemplates();
    } catch (e) {
      _toast('Could not load templates: $e');
      return;
    }
    if (templates.isEmpty) {
      _toast('No ID card templates yet — create one in the ID Templates tab first.');
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => IdCardPrintDialog(
        student: student,
        initialPhotoBytes: existingPhoto,
        templates: templates,
        onLoadTemplate: templatesRepo.fetchTemplate,
        onPrint: ({
          required photoBytes,
          required signatureBytes,
          required template,
        }) =>
            _printStudentId(student, photoBytes, signatureBytes, template),
      ),
    );
  }

  Future<Map<String, Uint8List>> _fetchTemplateImageBytes(
    IdCardTemplateDetail template,
  ) async {
    final templatesRepo = _idCardTemplatesRepo;
    final result = <String, Uint8List>{};
    if (templatesRepo == null) return result;
    final paths = {
      for (final e in [...template.frontLayout, ...template.backLayout])
        if (e.type == IdCardElementType.image && e.imagePath != null)
          e.imagePath!,
    };
    for (final path in paths) {
      try {
        final url = await templatesRepo.fetchTemplateImageUrl(path);
        if (url == null) continue;
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) result[path] = response.bodyBytes;
      } catch (e) {
        debugPrint('Could not load template image $path: $e');
      }
    }
    return result;
  }

  Future<void> _printStudentId(
    RfidStudentRow student,
    Uint8List photoBytes,
    Uint8List? signatureBytes,
    IdCardTemplateDetail template,
  ) async {
    final repo = _studentsRepo;
    if (repo == null) return;
    await repo.uploadStudentPhoto(studentId: student.id, bytes: photoBytes);
    if (signatureBytes != null) {
      await repo.uploadStudentSignature(studentId: student.id, bytes: signatureBytes);
    }
    final imageBytesByPath = await _fetchTemplateImageBytes(template);
    await printIdCard(
      frontLayout: template.frontLayout,
      backLayout: template.backLayout,
      data: IdCardPrintData(
        firstName: student.firstName,
        middleInitial: student.middleInitial,
        lastName: student.lastName,
        studentNumber: student.studentNumber,
        course: student.course,
        section: student.section,
        yearLevel: student.yearLevel,
        guardianName: student.guardianName,
        guardianContactNo: student.guardianContactNo,
        photoBytes: photoBytes,
        signatureBytes: signatureBytes,
      ),
      studentName: student.fullName,
      imageBytesByPath: imageBytesByPath,
    );
    await _loadStudents();
  }
```

- [ ] **Step 4: Run the full suite and analyze**

Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.
Run: `flutter analyze lib/documents/student_id_card_pdf.dart packages/rfid_management_module/lib/ui/id_card_print_dialog.dart lib/ui/it_technician_connected_page.dart` — expect no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/documents/student_id_card_pdf.dart packages/rfid_management_module/lib/ui/id_card_print_dialog.dart packages/rfid_management_module/pubspec.yaml lib/ui/it_technician_connected_page.dart
git commit -m "feat: wire template-driven printing into the Print ID flow"
```

(Only `git add` `packages/rfid_management_module/pubspec.yaml` if Step 2 actually needed to add `package:pdf` to it.)

---

### Task 10: Windows installer for the main dashboard

**Files:**
- Create: `windows/installer/dashboard_installer.iss`

**Interfaces:**
- Consumes: nothing from other tasks in this plan — this task only needs the app to build for Windows, which is already true.
- Produces: nothing later tasks depend on — this is the last task in the plan.

**Context:** This repo already has a working Inno Setup installer for the kiosk build, `windows/installer/kiosk_installer.iss` — read it in full first. This task creates a sibling script packaging `lib/main.dart` (the main login-gated dashboard, where this whole feature lives) instead of `lib/main_kiosk.dart`. `lib/main.dart` resolves to the SAME file-based env loader on Windows that `main_kiosk.dart` uses (both go through the conditional `lib/util/load_local_env.dart` export, which only differs between web and native — not between entrypoints), so this installer needs the exact same `.env`-copied-next-to-the-exe handling. `windows/installer/Output/` is already covered by `.gitignore` (added when the kiosk installer was built) — no `.gitignore` change needed.

- [ ] **Step 1: Write the installer script**

```ini
; STI Baliuag Dashboard — Inno Setup installer script.
;
; Packages the Windows release build of lib/main.dart (the main
; login-gated dashboard app — Registrar, IT Technician, Admin, etc. all
; sign in through this entrypoint) into a proper setup.exe: Start Menu
; shortcut, uninstaller, Programs & Features entry. Sibling to
; kiosk_installer.iss, which packages the separate lib/main_kiosk.dart
; entrypoint the same way.
;
; Prerequisite (one-time, on whichever machine builds the installer):
; install Inno Setup from https://jrsoftware.org/isinfo.php (free), which
; provides ISCC.exe (the command-line compiler this script is built with).
;
; IMPORTANT: lib/main.dart resolves to the same file-based env loader on
; Windows that lib/main_kiosk.dart uses (lib/util/load_local_env_io.dart
; — both go through the conditional lib/util/load_local_env.dart export,
; which only differs between web and native, not between entrypoints).
; So this installer copies .env into the install folder directly (see
; [Files] below) and every shortcut sets WorkingDir explicitly to {app},
; exactly like kiosk_installer.iss does and for the same reason.
;
; Build steps:
;   1. Make sure the repo root's .env has real SUPABASE_URL/SUPABASE_ANON_KEY.
;   2. From the repo root: flutter build windows --release
;      (lib/main.dart is the default entrypoint — no --target override
;      needed, unlike the kiosk build.)
;   3. From this directory: iscc dashboard_installer.iss
;   4. Output: windows/installer/Output/STI_Baliuag_Dashboard_Setup.exe
;
; Re-run all three steps whenever app code OR .env changes.

#define MyAppName "STI Baliuag Dashboard"
#define MyAppPublisher "STI College Baliuag"
#define MyAppExeName "capstone_dashboard.exe"
; Bump this alongside pubspec.yaml's version when the dashboard app changes.
#define MyAppVersion "1.0.0"

[Setup]
AppId={{A3E7B2D4-9F1C-4A8E-B5D2-7C6F0E3A8B91}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; Deployed on staff PCs administered by IT staff — install for all users,
; same as the kiosk installer.
PrivilegesRequired=admin
OutputBaseFilename=STI_Baliuag_Dashboard_Setup
OutputDir=Output
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
; Everything flutter build windows produces: the exe, flutter_windows.dll,
; plugin DLLs, and the data\ folder.
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; The repo root's .env, copied alongside the exe — see the IMPORTANT note
; above for why this (not a bundled asset) is what the app actually reads
; at runtime. Overwritten on every reinstall/upgrade so the deployed app
; always matches the source repo's current Supabase config.
Source: "..\..\.env"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Description: "Launch {#MyAppName} now"; Flags: nowait postinstall skipifsilent
```

- [ ] **Step 2: Verify the build**

Run: `flutter build windows --release` from the repo root — expect a clean build producing `build/windows/x64/runner/Release/capstone_dashboard.exe`.

If Inno Setup's `iscc` is available in this environment, run `iscc dashboard_installer.iss` from `windows/installer/` and confirm `Output/STI_Baliuag_Dashboard_Setup.exe` is produced. If `iscc` is NOT available, note in the task report that the script's compile couldn't be verified directly — its syntax was checked by close, section-by-section comparison against the already-working `kiosk_installer.iss` instead, with only the entrypoint-specific values (`MyAppName`, `AppId`, `OutputBaseFilename`, the build-step comment) actually differing.

- [ ] **Step 3: Commit**

```bash
git add windows/installer/dashboard_installer.iss
git commit -m "feat: add Windows installer script for the main dashboard build"
```

---

## Self-Review Notes

**Spec coverage:** Every section of the spec maps to a task — schema (Task 1), shared element model + repositories (Task 2), `guardian_contact_no`/signature storage (Task 3), the tab/list/editor-page scaffold (Task 4), the full editor interaction set split across three increments (Tasks 5-7, matching the spec's "Editor UI" section's full interaction list), signature capture (Task 8), print flow integration + renderer replacement (Task 9), and the Windows installer (Task 10). The spec's Non-goals (Topaz, Fingerprint, Data Entry/Report replication, OS clipboard, group resize, autosave) are called out explicitly in this plan's Global Constraints and never implemented in any task.

**Placeholder scan:** No task leaves a TODO, an "add appropriate handling"-style instruction, or an unimplemented function in its FINAL code — Task 9's `_buildPreviewPdf` initially sketched as an `UnimplementedError` stand-in was caught during this self-review and replaced with the actual implementation before this plan was finalized.

**Type consistency:** `IdCardTemplateElement`/`IdCardElementType`/`IdDataFieldKey`/`IdCardTemplateSummary`/`IdCardTemplateDetail`/`idCardWidthPt`/`idCardHeightPt` are defined once, in Task 2, and every later task (4, 5, 6, 7, 9) imports and uses them by those exact names — no task redefines or renames them. `IdCardTemplateEditorPage`'s constructor is introduced in Task 4 as `{templateName, initialFrontLayout, initialBackLayout, onSave}` and stays fixed through Tasks 5 and 6; Task 7 is the one documented exception, adding `onUploadImage` (and Task 7 explicitly updates every existing test construction site to match). `_selectedIds` is introduced as a `Set<String>` in Task 5 specifically so Task 6's multi-select work is additive rather than a structural rewrite — confirmed consistent across Tasks 5, 6, and 7's properties-panel code (`_selectedIds.length == 1` gating single-selection-only UI).
