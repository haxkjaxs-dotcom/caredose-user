# Admin Integration Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Plans can repeat on chosen weekdays or every N days, the web Dashboard shows real adherence data, and an admin can send a message that the patient app receives live over Supabase Realtime.

**Architecture:** One Supabase project (`eokqjjodfgdpgzievgln`). Two SQL changes in the web repo's `supabase/integration.sql` (`save_plan` rule parameters, `send_notification` RPC plus a Realtime publication entry). Web (React/Vitest) gets pure helper modules plus page wiring. The Flutter app gets one due-date function shared by the dose list and reminders, and a `NoticeSync` service (Realtime subscription plus pull) behind a repository interface so it is testable with fakes.

**Tech Stack:** Postgres/PGlite SQL tests (`pnpm test:sql`), React 19 + Vitest + `@supabase/supabase-js`, Flutter + `supabase_flutter`, `flutter_local_notifications`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-10-admin-integration-phase2-design.md` (in the app repo). Read it first; this plan only records decisions the spec leaves to the implementer.

**Repos:** WEB = `C:/Users/admin/Desktop/caredose-admin`, branch `feature/app-integration`. APP = `C:/Users/admin/Desktop/CareDose_User` (Flutter project in `caredose_app/`), branch `flutter-app`. Each task names its repo.

## Global Constraints

- All user-visible and SQL error text is Thai, SQL errors use `errcode = '22023'` for bad input and `'42501'` for missing permission (as in the existing `save_plan`).
- Weekday numbers are ISO: 1 = Monday … 7 = Sunday (equals Dart `DateTime.weekday`). Interval N is an integer 2–365 and counts from the plan's `start_date`.
- A plan has one rule applied to all its times; setting both `days_of_week` and `interval_days` is invalid.
- Notice title 1–100 characters, body 1–500 characters (characters, after trimming; Thai text counts per character, not byte).
- Dashboard day boundaries use Thai time (UTC+7).
- App keeps at most 100 shown-notice ids (`shared_preferences` key `caredose_shown_notices`) and the inbox lists the latest 30 notices.
- No Firebase, no Edge Function, no new package in either repo. Publishable key only; no secret in the web.
- Do not push or merge either repo, and do not touch the uncommitted edit to `caredose_app/lib/auth_gate.dart` (not part of this plan). Stage files by path, never `git add -A`.
- Every commit message ends with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

- Dose logged at 23:30 Thai (16:30 UTC) or 00:10 Thai (17:10 UTC the day before) must count on the Thai day, not the UTC day (Task 4).
- A day with no taken/skipped logs shows no rate (`null`), never 0 % (Task 4).
- Every-N-days rule: before `start`, across a month and year boundary, and with N larger than the plan length must give the right due days (Task 6).
- The same notice arriving through Realtime and through a pull at the same moment is shown once; a notice already shown but not yet marked read is not shown again (Task 7).
- Thai text of exactly 100/101 title characters and 500/501 body characters, and whitespace-only title/body, are accepted/rejected correctly in SQL and on the web (Tasks 2, 5).
- Local data saved before this change (no rule fields) loads as "every day", and signing out wipes shown-notice ids and the Realtime subscription so the next user inherits nothing (Tasks 6, 8).

---

### Task 1: SQL — `save_plan` rule parameters (WEB)

**Files:**
- Modify: `supabase/integration.sql` (the `save_plan` block and its `revoke`/`grant` lines; also any other reference to the 10-argument signature — `grep -rn "save_plan(" supabase/`)
- Create: `supabase/tests/70_plan_rules.sql` (same fixture style as `supabase/tests/40_save_plan.sql`; read that file first and copy its user/patient setup, run in `begin; … rollback;`)

**Interfaces:**
- Produces: `save_plan(p_plan_id uuid, p_patient_id uuid, p_medicine_id uuid, p_dose text, p_meal_relation text, p_start date, p_end date, p_note text, p_times text[], p_status text, p_days_of_week int[] default null, p_interval_days int default null) returns uuid`. The old 10-argument function no longer exists; calls with 10 named/positional args still resolve through the defaults.

- [ ] **Step 1: Write the failing test** `70_plan_rules.sql`, acting as admin on patient P1 with an active medicine. Assertions (use the `do $$ … assert … $$` / expected-exception style already used in `40_save_plan.sql`):
  - daily (both rule args null): schedule rows have `days_of_week is null and interval_days is null`.
  - weekdays `{1,3,5}` with times `{08:00,20:00}`: both rows have `days_of_week = '{1,3,5}'`, `interval_days is null`.
  - interval 2 with start set: both rows `interval_days = 2`, `days_of_week is null`.
  - rejected with `22023`: both rule args set; `{}` ; `{0}`; `{8}`; `{1,1}`; interval `1`; interval `366`; interval with `p_start is null` (start null already raises the start error first — assert that error instead, so also test interval with a valid start and `p_end` set).
  - changing rule on an existing plan that already has a log on its 08:00 schedule: call `save_plan` with the same times and a new rule; the schedule row id for 08:00 is unchanged, the log still exists, and the row now carries the new rule; a second identical call leaves `audit_logs` row count for `medication_schedules` unchanged (no write when the rule is the same).
  - old 10-argument call form (omitting the two new args) still works and yields a daily plan.
  - a caregiver with `can_manage_plan = false` calling with a rule still gets `42501`.
- [ ] **Step 2:** `pnpm test:sql` → FAIL in `70_plan_rules.sql` (unknown arguments).
- [ ] **Step 3: Implement** in `integration.sql`: `drop function if exists save_plan(uuid, uuid, uuid, text, text, date, date, text, text[], text);` before `create or replace function save_plan(…12 args…)`; move `revoke … from public, anon` / `grant … to authenticated` to the 12-argument signature. Validate (after the existing time checks, before the first write) with the Thai messages: both rule args → `'เลือกกฎได้เพียงแบบเดียว (เฉพาะวัน หรือ ทุก N วัน)'`; days empty/out of 1–7/duplicate → `'วันที่ทานต้องเป็น 1-7 ไม่ซ้ำกัน และเลือกอย่างน้อย 1 วัน'`; interval outside 2–365 → `'ทุก N วัน: N ต้องอยู่ระหว่าง 2 ถึง 365'`. For retained time rows run `update medication_schedules set days_of_week = …, interval_days = … where plan_id = pid and (days_of_week, interval_days) is distinct from (…, …)`; the final `insert … select` also writes the two columns.
- [ ] **Step 4:** `pnpm test:sql` → every file `ok` (the earlier `40_*`, `50_*`, `60_*` files must still pass; fix references rather than editing their assertions).
- [ ] **Step 5: Commit** (WEB) `supabase/integration.sql supabase/tests/70_plan_rules.sql` — `feat: add weekday and interval rules to save_plan`.

### Task 2: SQL — `send_notification` and Realtime publication (WEB)

**Files:**
- Modify: `supabase/integration.sql` (append a new numbered section)
- Create: `supabase/tests/80_send_notification.sql`

**Interfaces:**
- Produces: `send_notification(p_patient_id uuid, p_title text, p_body text) returns uuid` (security definer, `set search_path = public`, `revoke … from public, anon`, `grant … to authenticated`). Inserts `notifications(user_id = patients.user_id, type = 'admin_message', title, body, patient_id)` with trimmed title/body and an `audit_logs` row `action = 'send_notification'`.

- [ ] **Step 1: Write the failing test** `80_send_notification.sql` (fixture like Task 1 plus a linked patient P1 with `user_id` = patient user PU, an unlinked patient P2, and a second linked patient P3 for isolation). Assertions:
  - admin sends to P1 → returns uuid; one `notifications` row with `user_id = PU`, `type = 'admin_message'`, `read = false`, title/body trimmed; one `audit_logs` row.
  - Acting as PU (set role/claims the same way the other tests do): `select` from `notifications` sees that row; acting as P3's user sees 0 rows.
  - doctor, caregiver, patient and a disabled admin calling it → `42501`.
  - P2 (no `user_id`) → error text `'ผู้ป่วยรายนี้ยังไม่ได้เชื่อมแอป'`; unknown patient id → `22023`.
  - title: `''`, `'   '`, 101 Thai characters (`repeat('ก', 101)`) rejected; 100 Thai characters accepted. body: `''`, whitespace-only, 501 characters rejected; 500 accepted. Rejected calls leave `notifications` count unchanged.
- [ ] **Step 2:** `pnpm test:sql` → FAIL (function missing).
- [ ] **Step 3: Implement** in `integration.sql`, validating before the first write, errors in Thai (`'กรุณากรอกหัวข้อ'`, `'หัวข้อต้องไม่เกิน 100 ตัวอักษร'`, `'กรุณากรอกข้อความ'`, `'ข้อความต้องไม่เกิน 500 ตัวอักษร'`, `'ไม่มีสิทธิ์ส่งข้อความ'` for permission). Use `has_role('admin') and is_active_user()` for the gate. Add a rerunnable `do $$ … $$` block that runs `alter publication supabase_realtime add table notifications` only when the publication exists and the table is not already in `pg_publication_tables` (PGlite has no such publication, so the block must be a no-op there, not an error). Comment the known `notif_u` gap from the spec (owner can edit own rows) next to the policy mention.
- [ ] **Step 4:** `pnpm test:sql` → every file `ok`.
- [ ] **Step 5: Commit** (WEB) `supabase/integration.sql supabase/tests/80_send_notification.sql` — `feat: add send_notification and publish notifications to Realtime`.

### Task 3: Web — plan rule helpers and form (WEB)

**Files:**
- Modify: `src/lib/plans.ts`, `src/lib/plans.test.ts`, `src/pages/Plans.tsx`

**Interfaces:**
- Produces in `src/lib/plans.ts`:
  - `export type RuleKind = 'daily' | 'weekdays' | 'interval'`
  - `export const WEEKDAY_NAMES: string[]` = `['จันทร์','อังคาร','พุธ','พฤหัสบดี','ศุกร์','เสาร์','อาทิตย์']` (index = ISO day − 1)
  - `export function ruleLabel(days: number[] | null, interval: number | null): string` → `'ทุกวัน'` (both empty, or all 7 days), `'จันทร์/พุธ/ศุกร์'` (sorted, joined with `/`), `'ทุก 2 วัน'`
  - `PlanForm` gains `ruleKind: RuleKind; days: number[]; interval: string`; `PlanRow.medication_schedules` items gain `days_of_week: number[] | null; interval_days: number | null`; `planRowToView` returns extra `rule: string; ruleKind; days; interval` taken from the schedule with the earliest `time_of_day`
  - `validatePlanForm` input gains `ruleKind, days, interval`; new messages `'เลือกวันที่ทานอย่างน้อย 1 วัน'` and `'ทุก N วัน: N ต้องเป็นจำนวนเต็ม 2-365'`
  - `planRpcArgs` adds `p_days_of_week: number[] | null` (sorted, only for `weekdays`) and `p_interval_days: number | null` (only for `interval`)

- [ ] **Step 1: Write the failing tests** in `plans.test.ts`: `ruleLabel(null,null)` and `ruleLabel([1,2,3,4,5,6,7],null)` → `'ทุกวัน'`; `ruleLabel([5,1,3],null)` → `'จันทร์/พุธ/ศุกร์'`; `ruleLabel(null,2)` → `'ทุก 2 วัน'`; `validatePlanForm` returns the two new messages for `weekdays` with `days: []`, and for interval `'1'`, `'366'`, `'abc'`, `''` but `null` for `'2'`/`'365'`; `planRpcArgs` for each kind (days sorted, other arg null); `planRowToView` rule from the earliest-time schedule when two rows disagree; `planToForm` round-trips the rule so editing/stopping a weekday plan keeps its rule.
- [ ] **Step 2:** `pnpm test` → FAIL.
- [ ] **Step 3: Implement** the interfaces above in `plans.ts`. In `Plans.tsx`: add `days_of_week, interval_days` to the `medication_schedules(...)` select, a "ความถี่" column showing `v.rule`, and in `PlanForm` a rule selector (select for the three kinds; seven day toggle buttons with `aria-pressed` for `weekdays`; a number input for `interval`); `blank()` uses `ruleKind: 'daily', days: [], interval: ''`; pass the three new fields to `validatePlanForm`.
- [ ] **Step 4:** `pnpm test` → PASS; `pnpm build` → success.
- [ ] **Step 5: Commit** (WEB) `src/lib/plans.ts src/lib/plans.test.ts src/pages/Plans.tsx` — `feat(web): weekday and interval rules in the plan form`.

### Task 4: Web — Dashboard with real data (WEB)

**Files:**
- Create: `src/lib/dashboard.ts`, `src/lib/dashboard.test.ts`
- Modify: `src/pages/Dashboard.tsx`

**Interfaces:**
- Produces in `dashboard.ts`:
  - `export type DashLog = { scheduled_at: string; status: 'pending'|'taken'|'skipped'|'missed'; is_late: boolean; medication_plans: { patient_id: string; patients: { full_name: string } | null } | null }`
  - `export const thaiDay = (iso: string): string` → `yyyy-mm-dd` of that instant in UTC+7
  - `export const thaiDayStartIso = (day: string): string` → ISO instant of `day` 00:00 at +07:00
  - `export function todayCounts(logs: DashLog[], now: Date): { taken: number; late: number; skipped: number }` (taken excludes late; only logs whose `thaiDay(scheduled_at)` equals `thaiDay(now.toISOString())`)
  - `export function dailyRate(logs: DashLog[], now: Date, days: number): { day: string; rate: number | null }[]` oldest → newest ending today; `rate = taken ÷ (taken + skipped)` as 0–100 integer, `null` when the denominator is 0; `pending`/`missed` ignored
  - `export function needsFollow(logs: DashLog[], now: Date): { patientId: string; name: string; skipped: number; late: number }[]` today only, patients with `skipped + late > 0`, most skipped first

- [ ] **Step 1: Write the failing tests** in `dashboard.test.ts` with fixed instants: `thaiDay('2026-11-09T17:10:00Z')` → `'2026-11-10'`; `thaiDay('2026-11-10T16:30:00Z')` → `'2026-11-10'`; `thaiDay('2026-11-10T17:00:00Z')` → `'2026-11-11'`; `thaiDayStartIso('2026-11-10')` → `'2026-11-09T17:00:00.000Z'`; `todayCounts` ignores yesterday-Thai logs and `pending`; `dailyRate` returns 7 entries, a no-log day is `null` (not 0), a day with 1 taken + 1 skipped is `50`, `pending` only is `null`; `needsFollow` groups by patient, counts late and skipped, excludes fully on-time patients, sorts by skipped desc.
- [ ] **Step 2:** `pnpm test` → FAIL.
- [ ] **Step 3: Implement** `dashboard.ts`. Rewrite `Dashboard.tsx` to stop using `D.*`, `patients`, `appts` from Ctx: on mount query `patients` count (`select('id', { count: 'exact', head: true })`) and `medication_logs` with `.select('scheduled_at, status, is_late, medication_plans(patient_id, patients(full_name))').gte('scheduled_at', thaiDayStartIso(<today − 6 days Thai>))`. Show four `Stat` cards (ผู้ป่วยในความดูแล, ทานแล้ววันนี้, ทานเลทวันนี้, ข้ามวันนี้), the 7-day rate as a simple bar list (a `null` day shows `-`), and the follow-up table with a button calling `openPatient(patientId)`. Remove the appointments card and stat. Loading, error (red `role="alert"` box like `Plans.tsx`) and empty states. Add a comment `shortcut: default 1000-row query limit, page the query if a deployment logs more than that in 7 days`.
- [ ] **Step 4:** `pnpm test` → PASS; `pnpm build` → success.
- [ ] **Step 5: Commit** (WEB) the three files — `feat(web): dashboard reads real adherence data`.

### Task 5: Web — send a message to a patient (WEB)

**Files:**
- Create: `src/lib/notices.ts`, `src/lib/notices.test.ts`, `src/pages/SendNotice.tsx`
- Modify: `src/pages/Patients.tsx` (`PatientDetail` header, around the `<h2>{p.full_name}</h2>` row)

**Interfaces:**
- Produces: `validateNotice(title: string, body: string): string | null` (trim first; `'กรอกหัวข้อ'`, `'หัวข้อต้องไม่เกิน 100 ตัวอักษร'`, `'กรอกข้อความ'`, `'ข้อความต้องไม่เกิน 500 ตัวอักษร'`; count with `[...s].length`) and `noticeRpcArgs(patientId: string, title: string, body: string)` → `{ p_patient_id, p_title: title.trim(), p_body: body.trim() }`. `SendNotice({ patientId, patientName, notify, onClose })` modal.

- [ ] **Step 1: Write the failing tests** in `notices.test.ts`: empty/whitespace title and body; `'ก'.repeat(100)` ok and `'ก'.repeat(101)` rejected; 500/501 body; an emoji counted as one character; `noticeRpcArgs` trims.
- [ ] **Step 2:** `pnpm test` → FAIL.
- [ ] **Step 3: Implement** `notices.ts`; `SendNotice.tsx` using `Modal`, `Field`, `inputCls`, `Btn` like `PlanForm`, calling `supabase.rpc('send_notification', noticeRpcArgs(...))`, showing the RPC error text in the red alert box and `notify('ส่งข้อความแล้ว')` then `onClose()` on success. In `PatientDetail` show a "ส่งข้อความ" button only when `role === 'Admin' && p.user_id` (cosmetic; the RPC is the gate).
- [ ] **Step 4:** `pnpm test` → PASS; `pnpm build` → success.
- [ ] **Step 5: Commit** (WEB) the four files — `feat(web): send a message to a linked patient`.

### Task 6: App — weekday/interval rules (APP)

**Files:**
- Modify: `caredose_app/lib/models/models.dart` (`Med`), `caredose_app/lib/models/remote_plan.dart`, `caredose_app/lib/logic/dose_items.dart`, `caredose_app/lib/services/notification_plan.dart`, and any other date-based `med.times` consumer (`grep -rn "\.times" caredose_app/lib` — route each date-aware loop through `isDueOn`)
- Test: `caredose_app/test/dose_items_test.dart`, `remote_plan_test.dart`, `models_test.dart`, `notification_plan_test.dart`, `app_state_test.dart`

**Interfaces:**
- Produces: `Med` gains `final List<int> days` (default `const []`) and `final int intervalDays` (default `0`), both in `toJson`/`fromJson` (invalid values — days outside 1–7, interval < 2 or > 365 — read as "not set"; missing keys read as "every day") and carried by `copyWith`. `RemotePlan` gains the same two fields (named params with defaults, so existing constructor calls compile) read from the schedule row with the earliest time; `toMed()` copies them. `bool isDueOn(Med med, String date)` in `dose_items.dart`: false before `start`/after `end` (existing rules); if `days` non-empty, due only when `DateTime.parse(date).weekday` is in `days` (days win over interval); else if `intervalDays >= 2` and `start` is non-empty, due only when `date >= start` and the whole-day difference from `start` (computed with `DateTime.utc`) is divisible by `intervalDays`; otherwise due.

- [ ] **Step 1: Write the failing tests:**
  - `isDueOn`: weekdays `[1,3,5]` — 2026-11-09 (Mon) true, 2026-11-10 (Tue) false, 2026-11-15 (Sun, `[7]`) true; interval 2 with start 2026-11-09 — 11-09 true, 11-10 false, 11-11 true, 11-08 false (before start); interval 3 with start 2026-12-30 — 2026-12-31 false, 2027-01-01 false, 2027-01-02 true (year boundary); interval 7 with start 2026-02-26 — 2026-03-05 true (month boundary); interval set but `start` empty → every day; `days` and `intervalDays` both set → days rule used; `end` before date → false.
  - `itemsFor` for a weekday med returns no items on a non-due day; `planNotifications` plans no reminders on non-due days within the 14-day window and the expected ones on due days.
  - `RemotePlan.fromJson`: rows with `days_of_week: [1,3]` are no longer skipped (times kept); rule taken from the earliest-time row when rows disagree; `interval_days: 1` → `intervalDays` 0.
  - `Med.fromJson` of a map without `days`/`intervalDays` → every day; JSON round-trip keeps both; `copyWith(times: …)` keeps the rule.
  - `AppState.applyRemote`: a plan whose only change is the rule counts as changed (data updated, scheduler `calls` +1), identical data does not.
- [ ] **Step 2:** `flutter test` → FAIL (run from `caredose_app/`).
- [ ] **Step 3: Implement** the interfaces; remove the "Weekday / interval schedules are not representable" row filter in `RemotePlan.fromJson` (keep the `time_of_day` length check); replace the inline start/end checks in `itemsFor` and `planNotifications` with `isDueOn`. If `applyRemote`'s change detection compares only some `Med` fields, extend it to include the rule fields.
- [ ] **Step 4:** `flutter test` → all PASS; `flutter analyze` → No issues.
- [ ] **Step 5: Commit** (APP) the changed lib and test files by path — `feat(app): honour weekday and every-N-days plan rules`.

### Task 7: App — notice sync service (APP)

**Files:**
- Create: `caredose_app/lib/models/notice.dart`, `caredose_app/lib/services/notice_repository.dart`, `caredose_app/lib/services/supabase_notice_repository.dart`, `caredose_app/lib/services/notice_sync.dart`, `caredose_app/test/fake_notice_repository.dart`, `caredose_app/test/notice_sync_test.dart`
- Modify: `caredose_app/lib/services/notification_service.dart` (add `show`)

**Interfaces:**
- Produces:
  - `class Notice { final String id, title, body; final DateTime createdAt; final bool read; factory Notice.fromJson(Json j) }` (missing/blank title → `''`; bad date → skipped by the repository)
  - `abstract class NoticeRepository { Future<List<Notice>> fetchUnread(); /* read=false, oldest first */ Future<List<Notice>> fetchRecent(int limit); /* newest first */ Future<void> markRead(List<String> ids); void Function() subscribe(void Function(Notice) onInsert); /* returns cancel */ }` — methods throw only `AuthFailure` (wrap with `guardCall` from `supabase_auth_repository.dart`, as `SupabaseMedRepository` does)
  - `abstract class NoticeDisplay { Future<void> show(int id, String title, String body); }`; `NotificationService implements NoticeDisplay` (immediate `_plugin.show` on a new Android channel `admin_messages` / name `ข้อความจากผู้ดูแล`; no-op when `!_ready`)
  - `class NoticeSync { NoticeSync(NoticeRepository repo, NoticeDisplay display, SharedPreferences prefs, {bool Function()? canPull}); Future<void> pull(); void start(); void stop(); Future<void> clearShown(); Future<List<Notice>> loadRecent(); }`
  - `SupabaseNoticeRepository(SupabaseClient c)`: queries table `notifications` for the signed-in user (RLS already scopes rows; `fetchRecent` uses `.order('created_at', ascending: false).limit(n)`); `subscribe` uses `c.channel(...).onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'notifications', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid), callback: …).subscribe()` and cancels with `c.removeChannel`; with no signed-in user it returns a no-op cancel.

- [ ] **Step 1: Write the failing tests** in `notice_sync_test.dart` with `FakeNoticeRepository` (records `markRead` calls, lets the test push a notice through the captured `subscribe` callback, can throw `AuthFailure`) and a fake `NoticeDisplay` (records shown titles):
  - `pull` with two unread notices → both shown oldest first, `markRead` called with their ids, ids stored under `caredose_shown_notices`.
  - A notice delivered by the subscription callback and then by `pull` (and the reverse order, and both started without awaiting) → shown exactly once.
  - Display ok but `markRead` throws `AuthFailure(network)` → no throw out of `pull`; next `pull` does not show it again but retries `markRead`.
  - `pull` while `canPull()` is false, or after `stop()`, does nothing; `start()` twice subscribes once; `stop()` calls the cancel function.
  - Shown-id list is capped at 100 (oldest dropped).
  - `clearShown()` empties the stored ids and the in-memory set (a notice with a previously shown id is shown again afterwards).
  - `fetchUnread` throwing `AuthFailure` → `pull` completes quietly; any other exception is logged, not rethrown.
  - `loadRecent` returns the repository's newest-first list, and `[]` on `AuthFailure`.
  - `Notice.fromJson`: ISO `created_at`, missing `body` → `''`.
- [ ] **Step 2:** `flutter test test/notice_sync_test.dart` → FAIL.
- [ ] **Step 3: Implement.** Dedupe by adding the id to the in-memory set synchronously before awaiting `display.show`; display id is `notificationId('notice|$id', repeat: false)` from `notification_plan.dart`; an id already in the set only retries `markRead`. Persist the set after each notice.
- [ ] **Step 4:** `flutter test` → all PASS; `flutter analyze` → No issues.
- [ ] **Step 5: Commit** (APP) the new and changed files by path — `feat(app): receive admin messages through Realtime and pull`.

### Task 8: App — wire notices, inbox screen, sign-out (APP)

**Files:**
- Create: `caredose_app/lib/screens/notices_screen.dart`, `caredose_app/test/notices_screen_test.dart`
- Modify: `caredose_app/lib/main.dart`, `caredose_app/lib/lifecycle_reloader.dart`, `caredose_app/lib/screens/settings_sheet.dart`, `caredose_app/test/settings_sheet_test.dart` (and `test/helpers.dart` if the shared test app needs a `NoticeSync` provider)

**Interfaces:**
- Consumes: `NoticeSync`, `Notice` from Task 7.
- Produces: `class NoticesScreen extends StatelessWidget` (reads `NoticeSync` with `context.read`, `FutureBuilder` over `loadRecent()`; list of title, body, Thai date/time via the existing `thai_date.dart` helpers; empty state `'ยังไม่มีข้อความจากผู้ดูแล'`; shows at most the 30 latest).

- [ ] **Step 1: Write the failing tests:** `notices_screen_test.dart` — shows each notice's title and body, the empty text for `[]`; `settings_sheet_test.dart` — a button `'ข้อความจากผู้ดูแล'` exists and tapping it opens `NoticesScreen`.
- [ ] **Step 2:** `flutter test` on those files → FAIL.
- [ ] **Step 3: Implement.** `main.dart`: create `SupabaseNoticeRepository(Supabase.instance.client)` and `NoticeSync(repo, service, prefs, canPull: () => auth.status == AuthStatus.ready)`; in `syncReminders()` call `noticeSync.pull(); noticeSync.start();` when ready and `noticeSync.stop();` otherwise; in `onSignedOut` also call `noticeSync.clearShown()`; add `Provider<NoticeSync>.value(value: noticeSync)`. `lifecycle_reloader.dart`: also `context.read<NoticeSync>().pull()` on resume. `settings_sheet.dart`: `OutlinedButton` "ข้อความจากผู้ดูแล" placed above the sign-out button, pushing `NoticesScreen` with `Navigator.of(context).push(MaterialPageRoute(...))`. Update any test harness that builds the app tree so it provides a `NoticeSync` (with fakes) wherever `LifecycleReloader` or `SettingsSheet` is pumped.
- [ ] **Step 4:** `flutter test` → all PASS; `flutter analyze` → No issues; `flutter build apk --debug` → success.
- [ ] **Step 5: Commit** (APP) by path — `feat(app): admin message inbox and sync wiring`.

### Task 9: Final check and handoff (both repos)

- [ ] **Step 1:** WEB: `pnpm test`, `pnpm test:sql`, `pnpm build`; APP (in `caredose_app/`): `flutter analyze`, `flutter test`, `flutter build apk --debug` → all pass. Fix anything red before continuing; report real output, not a summary.
- [ ] **Step 2 (stop and tell the user):** the user must run the new `supabase/integration.sql` in the SQL Editor of `eokqjjodfgdpgzievgln` (it drops and recreates `save_plan` and adds `send_notification` plus the Realtime entry), and confirm in Dashboard → Database → Replication that `notifications` is in `supabase_realtime`. Remind them to use test phone numbers and fake data only.
- [ ] **Step 3:** after the user confirms: run `pnpm dev`, sign in as admin, create a plan for Mon/Wed/Fri and another every 2 days; run the app on an emulator signed in as the linked patient → only due days appear and reminders follow; mark a dose → Dashboard counts change; send a message from the patient page with the app open → local notification appears at once; close the app, send another, reopen → it appears; open settings → "ข้อความจากผู้ดูแล" lists both; sign out and in as another patient → no old messages. Take screenshots where possible.
- [ ] **Step 4:** report to the user what was verified for real and what was not (the real database beyond PGlite — including whether Realtime delivered — iOS, release build, PDPA), and ask before any push or merge of either repo.
