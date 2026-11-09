# CareDose — Admin Web Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ผู้ดูแลเพิ่มผู้ป่วย (เบอร์โทร) และแผนยาบนเว็บ → ผู้ป่วยล็อกอินแอปด้วยเบอร์ + OTP เห็นยาและได้แจ้งเตือน → การกดทานยาในแอปขึ้นไปให้ผู้ดูแลเห็นบนเว็บ

**Architecture:** ฐานข้อมูล Supabase `eokqjjodfgdpgzievgln` ของเว็บเป็นฐานเดียว เพิ่มฟังก์ชัน SQL (`claim_my_patient`, `save_my_profile`, `save_plan`, ทริกเกอร์ audit) ที่ทดสอบในเครื่องด้วย PGlite (Postgres WASM) ก่อนผู้ใช้รันจริง; เว็บเติมหน้าแผนยา/ประวัติ; แอปสลับมาใช้ฟังก์ชันและตารางของเว็บ โดยยาเป็นข้อมูลจากเซิร์ฟเวอร์ (สำเนาในเครื่อง) และบันทึกการทานยาส่งผ่านคิว

**Tech Stack:** PostgreSQL/Supabase (RLS, plpgsql), `@electric-sql/pglite` (ทดสอบ SQL), Vite + React + TypeScript + Vitest (เว็บ), Flutter + `supabase_flutter` (แอป)

**Spec:** `docs/superpowers/specs/2026-11-09-admin-integration-design.md` (อ่านคู่กับ `2026-11-05-login-profile-design.md`)

## Global Constraints

- สองรีโป: แอป `C:/Users/admin/Desktop/CareDose_User` (branch `flutter-app`), เว็บ clone ที่ `C:/Users/admin/Desktop/caredose-admin` จาก `https://github.com/haxkjaxs-dotcom/caredose-admin.git` บน branch `feature/app-integration`
- **ห้าม push เว็บหรือ merge เข้า `main` ของเว็บโดยไม่ได้รับอนุญาตจากผู้ใช้** (push `main` ของเว็บ deploy GitHub Pages อัตโนมัติ) push แอปได้เฉพาะเมื่อผู้ใช้สั่ง
- ฐานข้อมูลจริงรันโดยผู้ใช้ผ่าน SQL Editor เท่านั้น เครื่องมือ Supabase ของผู้ช่วยมองไม่เห็นโปรเจกต์ `eokqjjodfgdpgzievgln`; ห้ามใส่ `service_role`/secret key ที่ใดเลย ใช้เฉพาะ publishable key
- เบอร์: เปรียบเทียบด้วย `norm_phone` (`0812345678` = `66812345678` = `+66 81-234-5678`); รูปที่ผู้ดูแลกรอกในเว็บต้องเป็นมือถือไทย 10 หลักขึ้นต้น 06/08/09
- `integration.sql` รันซ้ำได้ (`create or replace`, `if not exists`, `drop ... if exists`); ฟังก์ชันที่ผู้ใช้เรียกต้อง `security definer` + `set search_path = public` + `revoke ... from public, anon` + `grant ... to authenticated`
- ข้อความ UI ภาษาไทยตามที่ระบุในแต่ละงาน; ค่า `p_consent_version = '2026-11'`; `is_late` = ทานเกิน 60 นาทีหลังเวลาที่กำหนด
- คำสั่งแอปรันจาก `caredose_app/`; คำสั่งเว็บรันจากโฟลเดอร์ `caredose-admin`
- ทุก commit ลงท้าย `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`

## Review Focus

1. เบอร์ที่ผู้ดูแลกรอกรูปแบบต่างจากที่ยืนยัน OTP (`0812345678` / `66812345678` / `+66 81-234-5678`) ต้องจับคู่ถูกคน (Task 2)
2. เบอร์ซ้ำในผู้ป่วยสองแถว → ต้องปฏิเสธการผูก ไม่ผูกผิดคน (Task 2)
3. admin ปิดบัญชีผู้ป่วยหลังผูกแล้ว ผู้ป่วยเปิดแอปใหม่ → การผูกซ้ำต้องไม่เปิดบัญชีกลับ (Task 2)
4. ลบเวลาทานที่เคยมีบันทึกแล้วผ่าน `save_plan` ต้องถูกปฏิเสธ (ไม่ลบประวัติเงียบ ๆ) (Task 4)
5. กดทานตอนไม่มีเน็ต แล้วปิดแอปก่อนส่ง → เปิดใหม่ต้องส่งครั้งเดียว ไม่ซ้ำ และไม่หาย (Task 12)

---

### Task 1: เตรียมรีโปเว็บและชุดทดสอบ SQL (PGlite)

**Files (รีโปเว็บ):**
- Create: `supabase/tests/harness.mjs`, `supabase/tests/00_auth_stub.sql`, `supabase/tests/10_baseline_rls.sql`
- Modify: `package.json` (devDependency `@electric-sql/pglite`, script `test:sql`)

**Interfaces:**
- Produces: คำสั่ง `pnpm test:sql` — เริ่ม PGlite ใหม่, รัน `00_auth_stub.sql`, `supabase/schema.sql`, `supabase/security_fixes.sql`, `supabase/integration.sql` (ถ้ามี) แล้วรันไฟล์ `supabase/tests/[1-9]*.sql` ตามลำดับชื่อ; ล้มเมื่อมี SQL error ใด ๆ (ไฟล์ทดสอบใช้ `do $$ ... assert ... $$` หรือ `raise exception`)
- `00_auth_stub.sql`: schema `auth`, ตาราง `auth.users(id uuid pk default gen_random_uuid(), email text, phone text, raw_user_meta_data jsonb default '{}')`, ฟังก์ชัน `auth.uid()` อ่าน `request.jwt.claims->>'sub'` (ว่าง = null), role `anon`, `authenticated` (nologin) — ให้ผลเหมือน Supabase สำหรับ `set local role authenticated` + `set_config('request.jwt.claims', ..., true)`

- [ ] **Step 1:** `git clone https://github.com/haxkjaxs-dotcom/caredose-admin.git C:/Users/admin/Desktop/caredose-admin`; `git checkout -b feature/app-integration`; `pnpm install`; `pnpm add -D @electric-sql/pglite`
- [ ] **Step 2: เขียนเทสต์ที่ fail** `10_baseline_rls.sql` (สร้างผู้ใช้ A, B ใน `auth.users` + `profiles` ที่ `is_active=true` + `patients` ของแต่ละคนที่ `user_id` ชี้ถึงตัวเอง): ผู้ป่วย A `select` จาก `patients` เห็นเฉพาะแถวตัวเอง; A เห็นแผนยา/บันทึกของ B = 0 แถว; บัญชีที่ `is_active=false` เห็น 0 แถวทุกตาราง; ผู้ป่วย A สั่ง `update patients set user_id = <B>` แล้วถูกปฏิเสธ (`42501`); ญาติที่ `can_manage_plan = false` เพิ่ม `medication_plans` ไม่ได้
- [ ] **Step 3:** รัน `pnpm test:sql` → FAIL (ยังไม่มี harness)
- [ ] **Step 4:** เขียน `harness.mjs` + `00_auth_stub.sql` + สคริปต์ใน `package.json`; ถ้า PGlite รัน schema.sql ไม่ได้ ให้หาสาเหตุ (เช่น `create type`, identity, security definer) และ ledger ruling; ห้ามแก้ `schema.sql` เดิม
- [ ] **Step 5:** `pnpm test:sql` → PASS (baseline RLS ของ schema เดิมผ่าน; ถ้าล้ม แปลว่าเจอช่องโหว่จริงของ schema เดิม ให้รายงานผู้ใช้ ไม่แก้เงียบ ๆ)
- [ ] **Step 6:** commit ในรีโปเว็บ `test: add PGlite SQL harness and baseline RLS checks`

### Task 2: `norm_phone`, คอลัมน์ใหม่ และ `claim_my_patient`

**Files (รีโปเว็บ):**
- Create: `supabase/integration.sql`, `supabase/tests/20_claim.sql`

**Interfaces:**
- Consumes: harness (Task 1)
- Produces ใน `integration.sql`:
  - `alter table patients add column if not exists nickname text, add column if not exists profile_completed_at timestamptz`
  - `norm_phone(text) returns text` immutable (spec)
  - `claim_my_patient() returns uuid` (spec: idempotent; ไม่เจอ → `null`; ซ้ำหลายแถว → `raise exception 'เบอร์ซ้ำในระบบ' using errcode = 'P0001'`; ผูก = ตั้ง `patients.user_id`, เพิ่ม role `patient`, `profiles.is_active = true`, `profiles.phone`, audit `claim_patient`)
  - `guard_admin_columns` ปรับเงื่อนไข: บล็อกเฉพาะเมื่อ `auth.uid() is not null and not has_role('admin') and current_user in ('authenticated','anon')`

- [ ] **Step 1: เขียนเทสต์ที่ fail** `20_claim.sql` (ผู้ใช้ใน `auth.users` มี `phone` รูป `66812345678`):
  - `norm_phone`: `'0812345678'`, `'66812345678'`, `'+66 81-234-5678'`, `'081-234-5678'` → `'0812345678'`; `''`/null → `''`/null
  - ผู้ป่วยในระบบเบอร์ `0812345678` ยังไม่มี `user_id` → `claim_my_patient()` ในฐานะผู้ใช้นั้นคืน id ผู้ป่วย, `patients.user_id` = uid, มี role `patient`, `profiles.is_active = true`, มี `audit_logs` แถว `claim_patient` (**Review Focus 1**: ทดสอบด้วยเบอร์ที่เก็บเป็น `+66 81-234-5678` และ `66812345678` ด้วย)
  - ไม่มีผู้ป่วยตรงเบอร์ → คืน `null` และไม่เปลี่ยนอะไร
  - **Review Focus 2:** ผู้ป่วยสองแถวเบอร์เดียวกัน (ทั้งคู่ไม่มีเจ้าของ) → โยน `P0001` และไม่ผูกแถวใดเลย
  - เรียกซ้ำหลังผูกแล้ว → คืน id เดิม ไม่เกิด audit เพิ่ม
  - **Review Focus 3:** admin ตั้ง `profiles.is_active = false` ของผู้ใช้ที่ผูกแล้ว → `claim_my_patient()` อีกครั้งคืน id เดิมแต่ `is_active` ยัง `false`
  - ผู้ใช้ที่เบอร์ตรงกับผู้ป่วยที่มีเจ้าของอื่นแล้ว → คืน `null` (ไม่แย่ง)
  - ผู้ใช้ไม่มี `auth.uid()` (anon) เรียกไม่ได้ (`42501` หรือ permission denied)
  - หลังผูกแล้ว ผู้ป่วยแก้ `patients.user_id` ตัวเองโดยตรงยังถูกบล็อก (guard ยังทำงานเมื่อเรียกตรงในฐานะ `authenticated`)
- [ ] **Step 2:** `pnpm test:sql` → FAIL (ไม่มีฟังก์ชัน)
- [ ] **Step 3:** implement ใน `integration.sql` ตามสเปก (ใช้ `has_role`/`is_active_user` ที่มีอยู่)
- [ ] **Step 4:** `pnpm test:sql` → PASS (รวมเทสต์เดิมทุกไฟล์)
- [ ] **Step 5:** commit `feat: add norm_phone and claim_my_patient`

### Task 3: `save_my_profile`

**Files (รีโปเว็บ):** Modify `supabase/integration.sql`; Create `supabase/tests/30_save_profile.sql`

**Interfaces:**
- Produces: `save_my_profile(p_nickname text, p_full_name text, p_age int, p_conditions text[], p_consent_version text) returns void` ตามสเปก (ตรวจความยาว/อายุ/ไม่ว่าง; อัปเดต `patients.nickname/full_name/age/conditions/profile_completed_at`, `profiles.full_name`; เพิ่ม `consents`; audit พร้อมค่าเก่า/ใหม่ใน `old_value`/`new_value`)

- [ ] **Step 1: เขียนเทสต์ที่ fail:** ผู้ป่วยที่ผูกแล้วบันทึกสำเร็จ → `patients` มีค่าใหม่ (`conditions = 'เบาหวาน, โรคไต'`), `profile_completed_at` ไม่ null, มีแถว `consents(version='2026-11', given_by=user)`, `profiles.full_name` ถูกอัปเดต; ผู้ใช้ที่ยังไม่มีแถวผู้ป่วย → `42501`; ชื่อเล่น `''`/51 ตัวอักษร, ชื่อจริง 101 ตัวอักษร, อายุ `0`/`121`, `p_conditions = '{}'`, consent_version ว่าง → ข้อผิดพลาด (ข้อความไทยตามฟิลด์) และไม่เกิดการเปลี่ยนแปลงใดเลย (ธุรกรรมคงเดิม); ผู้ป่วย A เรียกแล้วแถวของ B ไม่เปลี่ยน
- [ ] **Step 2:** รัน → FAIL; **Step 3:** implement; **Step 4:** `pnpm test:sql` → PASS
- [ ] **Step 5:** commit `feat: add save_my_profile`

### Task 4: `save_plan` และทริกเกอร์ audit

**Files (รีโปเว็บ):** Modify `supabase/integration.sql`; Create `supabase/tests/40_save_plan.sql`, `supabase/tests/50_rls_check.sql`

**Interfaces:**
- Produces: `save_plan(p_plan_id uuid, p_patient_id uuid, p_medicine_id uuid, p_dose text, p_meal_relation text, p_start date, p_end date, p_note text, p_times text[], p_status text) returns uuid` ตามสเปก; ทริกเกอร์ audit (`after insert or update or delete`, security definer) บน `medication_plans`, `medication_schedules`
- `50_rls_check.sql` ใช้เป็นไฟล์ที่ผู้ใช้รันเองใน SQL Editor ได้ (ล้อมด้วย `begin; ... rollback;`, ล้มด้วย `raise exception`)

- [ ] **Step 1: เขียนเทสต์ที่ fail** `40_save_plan.sql`:
  - admin สร้างแผน (ยา, dose `1 เม็ด`, `หลังอาหาร`, ช่วงวัน, เวลา `{08:00,18:00}`) → ได้ plan id, มี `medication_schedules` 2 แถว (`days_of_week`/`interval_days` null), audit 3 แถว (plan + 2 schedules)
  - แพทย์ที่ผูกกับผู้ป่วยทำได้; แพทย์ที่ไม่ผูก → `42501`; ญาติที่ `can_manage_plan = false` → `42501`; ญาติที่ `can_manage_plan = true` ทำได้; บัญชี `is_active=false` → `42501`
  - ตรวจข้อมูล: dose ว่าง, `p_end < p_start`, `p_times` ว่าง/ซ้ำ/รูป `8:00`/`24:00`, `p_status = 'x'`, ยา `is_active = false` → ข้อผิดพลาดและไม่มีแถวเกิดขึ้น
  - แก้ไขแผน: เปลี่ยนเวลา `{08:00,18:00}` → `{08:00,20:00}` เมื่อ `18:00` ยังไม่มีบันทึก → แถว `08:00` คง `id` เดิม, `18:00` ถูกลบ, `20:00` ถูกเพิ่ม
  - **Review Focus 4:** เมื่อ `18:00` มี `medication_logs` อยู่แล้ว ความพยายามเอาเวลานั้นออกโยนข้อผิดพลาด (ข้อความบอกให้หยุดแผนแล้วสร้างใหม่) และ `medication_logs` เดิมยังอยู่ครบ; การหยุดแผน (`p_status = 'stopped'` โดยไม่ลบเวลา) ทำได้
  - `50_rls_check.sql`: ผู้ป่วย A อ่านแผน/บันทึก/ผู้ป่วยของ B ไม่ได้; ผู้ป่วยเพิ่ม `medication_logs` ของตัวเองได้เมื่อ `recorded_by = uid` และของคนอื่นไม่ได้; ผู้ป่วยแก้ `medication_logs` เกิน 24 ชั่วโมงหลังเวลากำหนดไม่ได้ (0 แถวถูกแก้); ญาติแก้แผนยาไม่ได้; ผู้ป่วยแก้แผนยาตัวเองไม่ได้
- [ ] **Step 2:** รัน → FAIL; **Step 3:** implement (ทำแผน+เวลาในธุรกรรมเดียว; เทียบเวลาด้วยค่า `time` ไม่ใช่ข้อความ); **Step 4:** `pnpm test:sql` → PASS
- [ ] **Step 5:** commit `feat: add save_plan, plan audit triggers and RLS checks`

### Task 5: เว็บ — ตัวช่วยบริสุทธิ์และชุดทดสอบ

**Files (รีโปเว็บ):** Create `src/lib/plans.ts`, `src/lib/plans.test.ts`; Modify `package.json` (devDependency `vitest`, script `test`)

**Interfaces:**
- Produces:
  - `isThaiMobile(s: string): boolean` (ตัดช่องว่าง/ขีด; 10 หลักขึ้นต้น 06/08/09)
  - `isHHmm(s: string): boolean`; `normalizeTimes(list: string[]): string[]` (ตัดว่าง/ซ้ำ เรียง)
  - `validatePlanForm(f: {medicineId: string; dose: string; start: string; end: string; times: string[]}): string | null` — ข้อความไทย: `เลือกยา`, `กรอกขนาดยา`, `กรอกวันเริ่ม`, `วันที่สิ้นสุดต้องไม่ก่อนวันที่เริ่ม`, `เพิ่มเวลาทานอย่างน้อย 1 เวลา (รูป HH:mm)`
  - `logStatusLabel(status: 'pending'|'taken'|'skipped'|'missed', isLate: boolean): string` → `ทานแล้ว` / `เลท` (taken + isLate) / `ยังไม่ได้ทาน` (skipped) / `ยังไม่บันทึก` (pending, missed)

- [ ] **Step 1: เขียน test ที่ fail:** `isThaiMobile('081-234-5678')` true, `'0212345678'`/`'081234567'`/`''` false; `isHHmm('08:00')` true, `'8:00'`,`'24:00'`,`'12:60'` false; `normalizeTimes(['18:00','08:00','08:00',''])` → `['08:00','18:00']`; `validatePlanForm` ทุกข้อความข้างบน และกรณีถูกต้อง → `null`; `logStatusLabel` ทุกค่า
- [ ] **Step 2:** `pnpm add -D vitest`; รัน `pnpm test` → FAIL; **Step 3:** implement; **Step 4:** `pnpm test` → PASS; `pnpm build` ผ่าน (type-check)
- [ ] **Step 5:** commit `feat(web): add plan form helpers`

### Task 6: เว็บ — หน้า "แผนยา" ต่อ Supabase

**Files (รีโปเว็บ):** Modify `src/pages/Plans.tsx` (และการเรียกใช้ใน `src/App.tsx` ถ้าจำเป็น)

**Interfaces:**
- Consumes: `save_plan` (Task 4), ตัวช่วย (Task 5), `supabase` client, `ui.tsx` (`Card`, `Btn`, `Field`, `inputCls`), รูปแบบหน้าอื่น (เช่น `Meds.tsx`)
- Produces: หน้าเลือกผู้ป่วย (จาก `patients`) → รายการแผน (`medication_plans` + `medicines(generic_name,trade_name)` + `medication_schedules(time_of_day)`) แสดง ยา/ขนาด/มื้อ/ช่วงวัน/เวลา/สถานะ; ปุ่ม "เพิ่มแผนยา", "แก้ไข", "หยุดแผน" (เรียก `rpc('save_plan', ...)`) แสดงเมื่อบัญชีนั้นมีสิทธิ์แก้ (admin หรือ `can_manage_plan` จากการลองอ่านบทบาทตาม `App.tsx`) — ความปลอดภัยพึ่ง RLS/ฟังก์ชัน ปุ่มแค่ซ่อน; ข้อผิดพลาดจากฟังก์ชันแสดงข้อความไทยของเซิร์ฟเวอร์

- [ ] **Step 1:** อ่าน `Meds.tsx`, `Patients.tsx`, `ui.tsx` เพื่อใช้รูปแบบเดียวกัน (สถานะโหลด/error/ว่าง)
- [ ] **Step 2: เขียน test ที่ fail** สำหรับตรรกะแปลงข้อมูลที่แยกออกเป็นฟังก์ชันบริสุทธิ์ใน `src/lib/plans.ts`: `planRowToView(row)` (รวมชื่อยา `trade_name || generic_name`, เวลาเรียง `HH:mm` ตัดวินาที, ช่วงวัน, ป้ายสถานะ `ใช้งาน`/`หยุดแล้ว`) ใน `plans.test.ts`; รัน → FAIL
- [ ] **Step 3:** implement `planRowToView` และหน้า `Plans.tsx` ตามอินเทอร์เฟซ; ฟอร์มใช้ `validatePlanForm`/`normalizeTimes` ก่อนเรียก RPC
- [ ] **Step 4:** `pnpm test` → PASS; `pnpm build` → สำเร็จ
- [ ] **Step 5:** commit `feat(web): wire medication plans page`

### Task 7: เว็บ — หน้า "ประวัติการทานยา"

**Files (รีโปเว็บ):** Modify `src/pages/Logs.tsx`; Modify `src/lib/plans.ts` + `plans.test.ts`

**Interfaces:**
- Produces: `logRowToView(row)` (ผู้ป่วย, ยา, เวลาที่กำหนด `d MMM yyyy HH:mm` เวลาท้องถิ่น, สถานะจาก `logStatusLabel`, เวลาที่บันทึก, ผู้บันทึก); หน้า: ตัวกรองผู้ป่วย/วันที่/สถานะ, `limit 200`, เรียง `scheduled_at desc` อ่านจาก `medication_logs` พร้อม `medication_plans(patient_id, patients(full_name), medicines(generic_name,trade_name))`

- [ ] **Step 1: เขียน test ที่ fail** `logRowToView` (taken+late → `เลท`, skipped → `ยังไม่ได้ทาน`, ชื่อยา fallback, เวลาไทย); **Step 2:** รัน → FAIL; **Step 3:** implement + หน้า; **Step 4:** `pnpm test` + `pnpm build` → ผ่าน
- [ ] **Step 5:** commit `feat(web): wire medication logs page`

### Task 8: เว็บ — สถานะ "เชื่อมแอปแล้ว" และตรวจเบอร์ในรายชื่อผู้ป่วย

**Files (รีโปเว็บ):** Modify `src/pages/Patients.tsx`

**Interfaces:**
- Consumes: `isThaiMobile` (Task 5); `PATIENT_COLS` ใน `Patients.tsx` (เพิ่ม `user_id`, `nickname`)
- Produces: คอลัมน์ `เชื่อมแอป` (`เชื่อมแล้ว` / `ยังไม่เชื่อม`); ฟอร์มเพิ่มผู้ป่วยบังคับเบอร์ตาม `isThaiMobile` (ข้อความ `กรุณากรอกเบอร์มือถือ 10 หลัก (ใช้เบอร์นี้ให้ผู้ป่วยเข้าแอป)`); แจ้งเตือนข้างเบอร์ถ้ามีผู้ป่วยอื่นใช้เบอร์เดียวกัน (เทียบด้วยการตัดอักขระที่ไม่ใช่ตัวเลข + แปลง `66` นำหน้าเป็น `0`)

- [ ] **Step 1: เขียน test ที่ fail** ฟังก์ชัน `samePhoneGroups(patients)` (คืนชุดเบอร์ที่ซ้ำ) ใน `src/lib/plans.ts`/`plans.test.ts`; **Step 2–3:** รัน FAIL → implement ฟังก์ชันและแก้หน้า; **Step 4:** `pnpm test` + `pnpm build` ผ่าน
- [ ] **Step 5:** commit `feat(web): show app link status and validate patient phone`

### Task 9: แอป — AuthRepository/AuthState ใช้ `claim_my_patient` และ `patients`

**Files (รีโปแอป):** Modify `caredose_app/lib/config.dart`, `lib/services/auth_repository.dart`, `lib/services/supabase_auth_repository.dart`, `lib/state/auth_state.dart`, `lib/auth_gate.dart`; Create `lib/screens/not_registered_screen.dart`; Modify `test/fake_auth_repository.dart`, `test/auth_state_test.dart`, `test/auth_gate_test.dart`, `test/helpers.dart`; Create `test/not_registered_test.dart`

**Interfaces:**
- Produces:
  - `config.dart`: `supabaseUrl = 'https://eokqjjodfgdpgzievgln.supabase.co'`, `supabasePublishableKey = 'sb_publishable_I2y5wnjrQLolW7GAv_zbmQ_MvPxF-nJ'`
  - `AuthRepository.claimPatient(): Future<String?>` (id ผู้ป่วย หรือ null)
  - `AuthFailureKind` เพิ่ม `duplicatePhone` (ข้อความ `เบอร์นี้ซ้ำในระบบ กรุณาติดต่อผู้ดูแล`) และ `rejected` (ข้อความ `ระบบไม่อนุญาตการทำรายการนี้`); `mapAuthError` แปลง `PostgrestException` code `P0001` ที่ข้อความมี `เบอร์ซ้ำ` → `duplicatePhone`, code `42501` → `rejected`
  - `SupabaseAuthRepository.loadProfile()` อ่าน `patients` (`nickname, full_name, age, conditions, profile_completed_at`) ของ `user_id = uid`; คืน `Profile` เมื่อ `profile_completed_at` ไม่ null (`conditions` แยกด้วย `, `, `consentAt = profile_completed_at`) ไม่งั้น `null`; `saveProfile` เรียก `rpc('save_my_profile', params: {p_nickname, p_full_name, p_age, p_conditions, p_consent_version: '2026-11'})`
  - `AuthStatus.notRegistered`; `AuthState.retry(): Future<void>` (= ทำ `_resolve` ใหม่); `_resolve` ใช้ทั้ง `init` และหลัง `verifyOtp`: `claimPatient()` → null → `notRegistered`; มี id → `loadProfile()` → null → `needsProfile`, มี → `ready`(+แคช, `onSignedIn` เฉพาะหลัง verify/save); `AuthFailure` ระหว่าง `init` ใช้แคชเหมือนเดิม; `duplicatePhone` → `notRegistered` พร้อมข้อความ (เก็บใน `AuthState.notice`)
  - `NotRegisteredScreen`: ข้อความ `ยังไม่พบเบอร์นี้ในระบบ กรุณาติดต่อผู้ดูแล` (หรือ `AuthState.notice` ถ้ามี), ปุ่ม `ลองใหม่` (เรียก `retry`), ปุ่ม `ออกจากระบบ` (`signOut`); `AuthGate` แสดงหน้านี้เมื่อ `notRegistered`

- [ ] **Step 1: เขียน test ที่ fail:** `FakeAuthRepository` เพิ่ม `claimResult`(String?) และ `claimCalls`; `AuthState`: claim null → `notRegistered` (ทั้งหลัง verify และ init), claim id + ไม่มีโปรไฟล์ → `needsProfile`, claim id + โปรไฟล์ → `ready`, `retry` หลังผู้ดูแลเพิ่มเบอร์ (เปลี่ยน `claimResult`) → `needsProfile`/`ready`, `duplicatePhone` → `notRegistered` + notice, offline ตอน init ใช้แคช; `mapAuthError` สองรหัสใหม่; widget: `NotRegisteredScreen` ปุ่มทั้งสอง, `AuthGate` เลือกหน้านี้; อัปเดตเทสต์เดิมให้เรียก claim
- [ ] **Step 2:** `flutter test` → FAIL; **Step 3:** implement; **Step 4:** `flutter test` → PASS; `flutter analyze` → No issues
- [ ] **Step 5:** commit `feat(app): claim patient by phone and read profile from patients`

### Task 10: แอป — แปลงแผนยา (`RemotePlan`) และ `MedRepository`

**Files (รีโปแอป):** Create `lib/models/remote_plan.dart`, `lib/services/med_repository.dart`, `lib/services/supabase_med_repository.dart`; Modify `lib/models/models.dart` (`AppData.scheduleIds`, seed เปล่า); Test: `test/remote_plan_test.dart`, `test/models_test.dart`

**Interfaces:**
- Produces:
  - `class PlanSchedule { final String id, time; }`; `class RemotePlan { final String id, name, dosage, meal, start, end, note; final List<PlanSchedule> schedules; Med toMed(); factory RemotePlan.fromJson(Map<String, dynamic>) }` — `fromJson` รับ JSON ของ PostgREST (`medication_plans` + `medicines` + `medication_schedules`) ตามตารางแปลงในสเปก; ตัดวินาทีของ `time_of_day`; ข้ามแถวเวลาที่ `days_of_week` หรือ `interval_days` ไม่ null; `Med.color` จากแฮชคงที่ของ plan id (`medColors`)
  - `abstract class MedRepository { Future<List<RemotePlan>> fetchPlans(); Future<List<RemoteLog>> fetchLogs(DateTime since); Future<void> upsertLog(LogOp op); }`; `class RemoteLog { final String planId, scheduleId, status; final DateTime scheduledAt; final DateTime? takenAt; }`; `class LogOp { final String planId, scheduleId, status; final DateTime scheduledAt; final DateTime? takenAt; final bool isLate; Map<String,dynamic> toJson(); factory LogOp.fromJson(...) }` (`status` = `taken|skipped|pending`; JSON เก็บเวลาเป็น ISO UTC)
  - `AppData.scheduleIds: Map<String, String>` คีย์ `planId|HH:mm` → schedule id (อยู่ใน `toJson/fromJson`); `AppData.seed` ไม่มียา/แพทย์/ญาติ/นัดหมาย (เหลือเฉพาะค่าตั้งต้น)
  - `SupabaseMedRepository`: `fetchPlans` ด้วย select `*, medicines(generic_name,trade_name,warning), medication_schedules(id,time_of_day,days_of_week,interval_days)` กรอง `status = 'active'`; `fetchLogs` กรอง `scheduled_at >= since`; `upsertLog` ใช้ `upsert(onConflict: 'schedule_id,scheduled_at')` ด้วย `recorded_by = auth.uid()`; ทุกเมธอดห่อด้วย `mapAuthError`

- [ ] **Step 1: เขียน test ที่ fail:** `RemotePlan.fromJson` กรณีปกติ (ชื่อยาใช้ trade_name ถ้ามี ไม่งั้น generic_name; `dosage`, `meal`, `note` ใช้ `doctor_note` ก่อน `warning`; `end_date` null → `''`; เวลา `08:00:00` → `08:00` เรียงเวลา); แถวเวลาที่มี `days_of_week` ถูกข้าม; `toMed()`/สี คงที่ต่อ id เดียวกัน; `LogOp` JSON round-trip; `AppData` JSON round-trip รวม `scheduleIds`; seed ไม่มียา
- [ ] **Step 2–4:** FAIL → implement → `flutter test` ทั้งหมด PASS (แก้เทสต์เดิมที่พึ่ง seed ยา ให้สร้างข้อมูลทดสอบของตัวเองใน `test/helpers.dart` โดยไม่เปลี่ยนพฤติกรรมที่ทดสอบ); `flutter analyze` ผ่าน
- [ ] **Step 5:** commit `feat(app): map server medication plans to Med`

### Task 11: แอป — ซิงก์ยา (MedSync) เข้า AppState

**Files (รีโปแอป):** Create `lib/services/med_sync.dart`; Modify `lib/state/app_state.dart`, `lib/main.dart`, `lib/lifecycle_reloader.dart`; Test: `test/med_sync_test.dart`, `test/app_state_test.dart`

**Interfaces:**
- Consumes: `MedRepository`, `RemotePlan`, `RemoteLog` (Task 10)
- Produces:
  - `AppState.applyRemote({required List<RemotePlan> plans, required List<RemoteLog> logs}): void` — แทน `data.meds` ทั้งชุดด้วย `plans.map(toMed)`, สร้าง `scheduleIds`, รวมบันทึกจากเซิร์ฟเวอร์เข้า `data.logs` (คีย์ `planId|yyyy-MM-dd|HH:mm` จาก `scheduledAt` เวลาท้องถิ่น; `taken`/`skipped` จากเซิร์ฟเวอร์ชนะ; `pending` ถูกละเลย; แผนที่หายไปไม่ลบ log เก่าในเครื่อง); บันทึก + `reschedule` เฉพาะเมื่อรายการยาหรือ log เปลี่ยนจริง (เทียบ JSON)
  - `class MedSync { MedSync(MedRepository repo, AppState state); Future<void> pull(); void start(); void stop(); }` — `pull` เรียก `fetchPlans` + `fetchLogs(now − 30 วัน)` แล้ว `applyRemote`; ถ้าโยน `AuthFailure` ไม่แก้ข้อมูล ไม่ propagate; `start` ตั้ง `Timer.periodic(5 นาที)`; ไม่ซ้อนกัน (ถ้ากำลัง pull อยู่ข้าม)
  - `main.dart`: สร้าง `MedSync` เมื่อ `AuthStatus.ready` (ใน `syncReminders`) เรียก `pull()` และ `start()`, หยุดเมื่อออกจาก ready; `LifecycleReloader` เรียก `pull()` เมื่อ resumed

- [ ] **Step 1: เขียน test ที่ fail:** `applyRemote` เปลี่ยนยา → `data.meds` ตรงกับแผน, `scheduleIds` ถูก, `reschedule` ถูกเรียก 1 ครั้ง; เรียกซ้ำด้วยข้อมูลเดิม → ไม่เรียก reschedule เพิ่ม; log จากเซิร์ฟเวอร์ (`scheduled_at` UTC → คีย์เวลาท้องถิ่นถูกต้อง) เข้า `data.logs`; แผนถูกหยุด (ไม่อยู่ในรายการ) → ยานั้นหายและ reschedule; `MedSync.pull` ด้วย repository จำลอง: สำเร็จ → อัปเดต, โยน `AuthFailure(network)` → ข้อมูลเดิมคงอยู่และไม่โยนต่อ, สองครั้งซ้อนกัน → เรียก repository ครั้งเดียว
- [ ] **Step 2–4:** FAIL → implement → `flutter test` PASS; `flutter analyze` ผ่าน
- [ ] **Step 5:** commit `feat(app): sync medication plans from the server`

### Task 12: แอป — ส่งบันทึกการทานยา (LogOutbox) และออกจากระบบ

**Files (รีโปแอป):** Create `lib/services/log_outbox.dart`; Modify `lib/state/app_state.dart`, `lib/main.dart`, `lib/state/auth_state.dart` (ลำดับออกจากระบบ), `lib/screens/settings_sheet.dart` (ข้อความเตือน), `lib/services/storage.dart`; Test: `test/log_outbox_test.dart`, `test/app_state_test.dart`, `test/settings_sheet_test.dart`

**Interfaces:**
- Consumes: `MedRepository.upsertLog`, `LogOp` (Task 10), `AppData.scheduleIds`
- Produces:
  - `class LogOutbox { LogOutbox(SharedPreferences prefs, MedRepository repo); List<LogOp> get pending; Future<void> add(LogOp op); Future<void> flush(); Future<void> clear(); }` — คิวเก็บใน `caredose_outbox` (JSON list, เรียงตามเวลาที่เพิ่ม); `add` แทนรายการเดิมที่ `scheduleId + scheduledAt` เดียวกัน (กดทาน→ยกเลิกต่อกันเหลือ op ล่าสุด); `flush` ส่งทีละรายการตามลำดับ, สำเร็จแล้วลบออก, `AuthFailure.network/unknown/rateLimited` → หยุดและเก็บที่เหลือไว้, `AuthFailure.rejected` → ทิ้งรายการนั้นแล้วทำต่อ; ไม่ส่งซ้ำแบบขนาน (flush ซ้อน → ข้าม)
  - `AppState` รับ `LogOutbox? outbox`: `mark`/`markMeal`/`undo`/`undoKeys`/`applyNotificationAction`(`taken`,`skip`) สร้าง `LogOp` จากคีย์ของรายการ (`planId = med.id`, `scheduleId = data.scheduleIds['planId|time']`, `scheduledAt` = เวลาท้องถิ่นของ dose → UTC; `taken` → `isLate = now − scheduledAt > 60 นาที`, `takenAt = now`; ยกเลิก → `status = 'pending'`, `takenAt = null`) แล้ว `outbox.add` ตามด้วย `flush` (ไม่ await ใน UI); ไม่มี `scheduleId` (ยังไม่ซิงก์) → ไม่ส่งและไม่ล้ม
  - `main.dart`: เรียก `flush()` ตอนเริ่ม, เมื่อ resumed, และหลัง `MedSync.pull` สำเร็จ
  - ออกจากระบบ: `AuthState.signOut` เรียก hook `beforeSignOut` (ใน `main`: `outbox.flush()` รอไม่เกิน 5 วินาที) ก่อนเรียก backend; จากนั้น `outbox.clear()` ใน `onSignedOut`; กล่องยืนยันเพิ่มบรรทัด `บันทึกการทานยาที่ยังส่งไม่ได้จะหายไป` เมื่อ `outbox.pending` ไม่ว่าง (หน้า settings อ่านผ่าน provider)

- [ ] **Step 1: เขียน test ที่ fail:**
  - `LogOutbox`: add 2 รายการ → ลำดับถูก, persist แล้วสร้างอ็อบเจ็กต์ใหม่จาก prefs เดิมยังเห็นครบ; `flush` สำเร็จส่งตามลำดับและคิวว่าง; **Review Focus 5:** `flush` ล้มด้วย network → ไม่ส่งซ้ำรายการที่สำเร็จไปแล้ว, รายการที่เหลือยังอยู่, สร้างอ็อบเจ็กต์ใหม่ (จำลองปิด/เปิดแอป) แล้ว `flush` → ส่งรายการที่เหลือครั้งเดียว (นับจำนวนการเรียก `upsertLog` ทั้งหมด = จำนวนรายการ ไม่มีซ้ำ); `rejected` → ถูกทิ้งแล้วทำรายการถัดไป; กด `taken` แล้ว `pending` ภายในคิวเดียว → เหลือ 1 op (`pending`); `flush` ซ้อนสองครั้ง → `upsertLog` ไม่ถูกเรียกซ้ำ
  - `AppState`: `mark(taken)` → `outbox.add` ด้วยค่าที่ถูก (`planId`, `scheduleId`, `scheduledAt` UTC, `isLate` ทั้งกรณีเกิน/ไม่เกิน 60 นาที), `markMeal` ส่งทุกรายการที่บันทึก, `undo` → `pending`, ไม่มี `scheduleIds` → ไม่เพิ่มคิวและไม่โยน; `applyNotificationAction('skip')` → `skipped`, `'notyet'` → ไม่เพิ่มคิว
  - ออกจากระบบ: มีคิวค้าง → กล่องยืนยันแสดงข้อความเตือน; ยืนยัน → เรียก flush ก่อน, `outbox.pending` ว่างหลังออก
- [ ] **Step 2–4:** FAIL → implement → `flutter test` PASS; `flutter analyze` ผ่าน; `flutter build apk --debug` สำเร็จ
- [ ] **Step 5:** commit `feat(app): send dose records to the server through an outbox`

### Task 13: ตรวจรวม (ผู้ใช้ต้องเตรียมฝั่ง Supabase)

- [ ] **Step 1:** รัน `pnpm test`, `pnpm test:sql`, `pnpm build` (เว็บ) และ `flutter analyze`, `flutter test`, `flutter build apk --debug` (แอป) → ทั้งหมดผ่าน
- [ ] **Step 2 (หยุดแจ้งผู้ใช้):** ส่งสิ่งที่ผู้ใช้ต้องทำเอง พร้อมขั้นตอน: (ก) รัน `supabase/integration.sql` ใน SQL Editor ของ `eokqjjodfgdpgzievgln` (ถ้ายังไม่เคยรัน `schema.sql`/`security_fixes.sql` ให้บอก — `security_fixes.sql` ถูกระบุว่าใช้แล้ว) (ข) รัน `supabase/tests/50_rls_check.sql` ยืนยันว่าไม่มี error (ค) เปิด Phone provider + เบอร์ทดสอบ `66812345678=123456` และวันหมดอายุไกลพอ (ง) มีบัญชี admin ของเว็บ (จ) ตรวจเรื่อง PDPA ก่อนใช้งานจริง
- [ ] **Step 3:** เมื่อผู้ใช้ตอบว่าเสร็จ: รันเว็บในเครื่อง (`pnpm dev`) ล็อกอิน admin → เพิ่มผู้ป่วยเบอร์ `0812345678` + แผนยา 1 ตัว 2 เวลา; รันแอปบน emulator ล็อกอินด้วยเบอร์ทดสอบ → ไม่พบเบอร์ (ถ้ายังไม่เพิ่ม) แล้วเพิ่มและกดลองใหม่ → กรอกโปรไฟล์ → เห็นยา → กดทานแล้ว → เว็บเห็นในประวัติ → admin หยุดแผน → แอปไม่แสดงยานั้นหลังซิงก์; ถ่ายภาพหน้าจอประกอบ
- [ ] **Step 4:** รายงานผู้ใช้: สิ่งที่ตรวจได้จริงและสิ่งที่ยังไม่ได้ตรวจ (ฐานข้อมูลจริงนอกจากการทดสอบของผู้ใช้, SMS จริง, iOS, release build); ถามก่อน push/merge รีโปเว็บและแอป
