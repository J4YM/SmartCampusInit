# Good Moral Form Auto-fill and Comparison Implementation Plan (piece 3 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox syntax.

**Goal:** The Good Moral request slip pre-fills from the student's record (still editable); the Discipline Officer (DO) sees the submitted slip next to what the school has on record with differences highlighted, and can flag the request or send it back to the student, who edits and resubmits.

**Architecture:** Store the slip as structured `form_data` jsonb (the existing `remarks` text blob stays for compatibility and the certificate). One shared pure-Dart model and comparer in `dashboard_layout` used by the student portal, parent portal and DO dashboard. Flag / send back / resubmit are SECURITY DEFINER RPCs; a resubmission moves the earlier submission into a `history` jsonb array.

**Tech Stack:** Flutter monorepo, Supabase Postgres RLS + RPC, recording-server repository tests, widget tests.

**Spec:** `docs/superpowers/specs/2026-10-22-do-owns-investigations-and-endorsements-design.md` goal 9.

## Global Constraints

- Netlify web build: Flutter 3.24.5, use `withOpacity`, not `withValues`.
- SQL is idempotent, run by the user; the implementer cannot run it, so its test script is written first.
- The DO cannot edit the student's answers; corrections to the certificate happen in the exported .docx outside the system. A flagged request still exports.
- Resubmission keeps the earlier submission in `history`.
- The school record has no address, middle name or "last attended"; those show "Not on record" and are never marked as mismatches.
- Student autofill uses what exists: last/first name, student number, section, contact (`profiles.phone_number`), A.Y. started (`students.enrollment_year`), school status "enrolled". The parent slip is not pre-filled.

## Review Focus

- A name written with different case, extra spaces or punctuation is not a mismatch.
- "BSIT 3-A" vs "BSIT 3A" is not a mismatch; "BSIT 3-A" vs "BSIT 3-B" is.
- A submission with no `form_data` (older requests) still opens in the DO panel with the old remarks text and no false mismatches.
- A student cannot resubmit a request that is not `Returned`, nor someone else's.
- Resubmitting twice keeps both earlier submissions in `history`.

## Tasks

### Task 1: Shared form model and comparer (`dashboard_layout`)
- Create `packages/dashboard_layout/lib/src/good_moral_form.dart`, export from `dashboard_layout.dart`; test `packages/dashboard_layout/test/good_moral_form_test.dart`.
- Produces: `class GoodMoralFormData { lastName, firstName, middleName, address, studentNumber, section, contactNumber, ayStarted, ayLastAttended, schoolStatus, reason }` (all `String`) with `toJson()` / `fromJson(Map)` using snake_case keys and `String remarksText(String fullNameLine)`-style `remarks` builder identical to today's blob; `class GoodMoralRecord { firstName, lastName, studentNumber, section, contactNumber, int? enrollmentYear }`; `enum FieldMatch { match, mismatch, notOnRecord }`; `class GoodMoralFieldCheck { label, submitted, onRecord, FieldMatch match }`; `List<GoodMoralFieldCheck> compareGoodMoralForm(GoodMoralFormData form, GoodMoralRecord record)` comparing last name, first name, student number, section (alphanumerics only, case-insensitive), contact (last 10 digits), A.Y. started (record year contained in the text), and listing middle name, address, last attended, school status as `notOnRecord`.
- Tests first: case/space/punctuation tolerance, section `3-A` vs `3A` match and `3-B` mismatch, contact `0917 123 4567` vs `+63 917 123 4567` match, A.Y. `2024-2025` vs year 2024 match, empty record field -> `notOnRecord`, JSON round trip.

### Task 2: Database
- Create `supabase/add_good_moral_form_data.sql`, `supabase/test_good_moral_form_data.sql`.
- Columns on `good_moral_requests`: `form_data jsonb`, `flag_note text`, `flagged_at timestamptz`, `history jsonb not null default '[]'`; status check gains `'Returned'`.
- `flag_good_moral_request(p_request_id uuid, p_note text, p_send_back boolean) returns void`: DO/Admin; note required; sets `flag_note`, `flagged_at`; `p_send_back` also sets `status='Returned'` and notifies the student (`user_id = student_id`).
- `resubmit_good_moral_request(p_request_id uuid, p_purpose text, p_remarks text, p_form_data jsonb) returns void`: caller is the request's student or a linked parent; only when `status='Returned'`; appends `{submitted_at, purpose, remarks, form_data, returned_note, returned_at}` to `history`, replaces the live values, `status='Pending'`, clears `flag_note`/`flagged_at`, notifies the DO role.
- Test script first (Admin session, rolled back): flag without send-back keeps `Pending`; send-back sets `Returned`; resubmit on `Pending` raises; resubmit twice yields `jsonb_array_length(history) = 2`.

### Task 3: Student and parent slips (autofill, structured submit, edit and resubmit)
- Modify both `good_moral_request_page.dart` files (student_portal_module, parent_portal_module), both home pages, `lib/data/student_portal_repository.dart`, `lib/data/parent_portal_repository.dart`, both connected pages, `GoodMoralRequestStatus` (both modules).
- `GoodMoralRequestPage({onSubmit, GoodMoralFormData? initial, String? returnNote})`; `onSubmit` gains `required Map<String, dynamic> formData`; initial values fill the controllers, school status and reason; the page shows `returnNote` in a banner when set.
- `GoodMoralRequestStatus` gains `String? flagNote`, `Map<String, dynamic>? formData`, `bool get isReturned`; the request row shows a Returned badge, the note and an **Edit & resubmit** button that opens the page with `initial` = that form and `onResubmit(requestId, ...)`.
- Repositories: `submitGoodMoralRequest` also sends `form_data`; `fetchMyGoodMoralRequests` selects `flag_note, form_data`; `resubmitGoodMoralRequest({requestId, purpose, remarks, formData})` calls the RPC; student only: `fetchGoodMoralPrefill(studentId) -> GoodMoralFormData` from `students` + `profiles` + `sections`.
- Tests first: page prefills and stays editable; submit emits `formData`; a returned request shows the note and opens prefilled; repository tests via the recording server.

### Task 4: DO comparison, flag and send back
- Modify `good_moral_models.dart`, `good_moral_view.dart`, the DO dashboard page, `lib/data/discipline_repository.dart`, `lib/ui/discipline_officer_connected_page.dart`.
- `GoodMoralRequestModel` and `GoodMoralSelectedStudent` gain `status`, `flagNote`, `GoodMoralFormData? formData`, `GoodMoralRecord? record`, `int historyCount`; `fetchGoodMoralRequests` selects `status, flag_note, form_data, history, students(... profiles(first_name,last_name,phone_number))`; `flagGoodMoralRequest(String requestId, String note, {required bool sendBack})`.
- The preview panel shows, for a request with `formData`: a "Submitted slip" card comparing each `GoodMoralFieldCheck` (mismatch highlighted red, `notOnRecord` muted); a banner when flagged/returned with the note; actions **Flag** and **Send back to student** (note dialog, note required) hidden when not callable (`onFlagRequest` null) or when the request is `Fulfilled`.
- Tests first: mismatch highlighted and match not; request without `formData` shows no comparison and no false mismatch; Flag and Send back call the callback with the note and `sendBack` flag; note required.

### Task 5: Checklist and verification
- Add the demo steps and `add_good_moral_form_data.sql` to `docs/superpowers/demo-checklist.md`; run the root suite, package suites and analyzer.
