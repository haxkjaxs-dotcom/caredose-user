# ญาติ/ผู้ดูแล ซิงก์สองทาง (แอป ↔ เว็บ Admin) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ญาติที่ผู้ป่วยเพิ่ม/แก้/ลบในแอปไปปรากฏในเว็บ Admin (หน้า "ญาติและผู้ดูแล") และญาติที่ Admin เพิ่มในเว็บมาปรากฏในแอป

**Architecture:** ใช้ตาราง `caregivers` + `patient_caregivers` เดิม ญาติจากแอปเป็นแถว `caregivers` ที่ `user_id` ว่างและ `added_by_patient = true` ผู้ป่วยจัดการผ่านฟังก์ชัน security definer สามตัว (`list_my_relatives`, `save_my_relative`, `delete_my_relative`) เซิร์ฟเวอร์เป็นข้อมูลหลัก แอปเก็บสำเนาใน `AppData.relatives` และทับด้วยผลดึงทุกรอบ `MedSync.pull`

**Scope (ผู้ใช้ตัดให้เรียบง่าย 2026-11-13):** ไม่ทำการ์ดญาติในหน้าข้อมูลผู้ป่วย (ใช้หน้า "ญาติและผู้ดูแล" เดิมที่เห็นข้อมูลอยู่แล้ว) และไม่ย้ายญาติเก่าที่เก็บในเครื่องขึ้นเซิร์ฟเวอร์ (ญาติที่เพิ่มก่อนอัปเดตจะถูกสำเนาจากเซิร์ฟเวอร์ทับ)

**Tech Stack:** Postgres/PGlite (`supabase/integration.sql`, `pnpm test:sql`), React + Vitest (เว็บ `C:\Users\admin\Desktop\caredose-admin`, branch `feature/app-integration`), Flutter (`C:\Users\admin\Desktop\CareDose_User\caredose_app`, branch `flutter-app`)

**Spec:** `docs/superpowers/specs/2026-11-13-relatives-sync-design.md` (รีโปแอป)

## Global Constraints

- ไม่เพิ่ม dependency ใหม่ทั้งแอปและเว็บ; ไม่แตะนโยบาย RLS เดิม; ไม่แตะ `caredose_app/lib/auth_gate.dart`
- ญาติจากแอป: `caregivers.user_id` ว่างเสมอ, `added_by_patient = true`, ผูกด้วย `patient_caregivers.status = 'confirmed'`, `can_manage_plan = false`, `can_manage_appt = false` ห้ามจับคู่หรือใช้แถว `caregivers` ที่มีอยู่แล้ว (แม้เบอร์ตรงกัน)
- ผู้ป่วยหาจาก `auth.uid()` → `patients.user_id` เท่านั้น ห้ามรับ id ผู้ป่วยจากไคลเอนต์; ผู้เรียกต้อง `is_active_user()` ไม่งั้น 42501
- ค่าจำกัด (ข้อผิดพลาด 22023 เมื่อเกิน): ชื่อ 1–100 ตัวอักษร, ความสัมพันธ์ ≤ 50 (ว่างได้), เบอร์ 1–20, ญาติที่ไม่ถูกเพิกถอนไม่เกิน 20 คนต่อผู้ป่วย; วัดหลังตัดช่องว่างหน้าหลัง นับเป็นตัวอักษร (`char_length`)
- `editable` = `added_by_patient` และแถวนั้นไม่ผูกกับผู้ป่วยคนอื่น
- ลบญาติที่ไม่ `editable` หรือแก้แถวของผู้ป่วยอื่น: 42501
- ข้อความแอปเป็นภาษาไทย; เพิ่ม/แก้/ลบต้องออนไลน์ ล้มเหลวแล้วสำเนาในเครื่องไม่เปลี่ยน
- ทุกงานตามรูปแบบทดสอบเดิม: SQL ใน `supabase/tests/92_relatives.sql` (ธุรกรรม `begin; … rollback;`), แอปใช้ `flutter test`, เว็บใช้ `pnpm test`

## Review Focus

1. ญาติจากแอปมีเบอร์เดียวกับบัญชีผู้ดูแลที่มีอยู่แล้ว → ต้องได้แถวใหม่ ไม่ผูกกับบัญชีนั้น และบัญชีนั้นยังเห็นผู้ป่วยไม่ได้ (SQL, Task 1)
2. ชื่อว่าง/ยาวเกิน, เบอร์ว่าง, ญาติคนที่ 21 → ไม่มีแถวถูกเขียน (SQL, Task 1) และแอปแสดงข้อความ ไม่ปิดฟอร์ม (Task 4)
3. ดึงรายชื่อล้ม (ออฟไลน์) ต้องไม่ลบสำเนาในเครื่อง (Task 3)
4. ดึงรายชื่อค้างอยู่ขณะผู้ป่วยกดบันทึก → ผลดึงเก่าต้องไม่ทับผลบันทึก (Task 3)
5. ญาติที่ Admin สร้างในแอปไม่มีปุ่มแก้/ลบ (Task 4)

---

### Task 1: ฐานข้อมูล — คอลัมน์ + ฟังก์ชันสามตัว + ทดสอบ SQL (รีโปเว็บ)

**Files:**
- Modify: `C:\Users\admin\Desktop\caredose-admin\supabase\integration.sql` (เพิ่มหัวข้อ `-- 18)` ท้ายไฟล์ รันซ้ำได้)
- Create: `C:\Users\admin\Desktop\caredose-admin\supabase\tests\92_relatives.sql`

**Interfaces:**
- Produces (ให้ Task 3 เรียกผ่าน `supabase.rpc`):
  - `list_my_relatives() returns table(id uuid, name text, relationship text, phone text, editable boolean)` เรียงตามชื่อแล้ว id; เฉพาะลิงก์ `status <> 'revoked'`
  - `save_my_relative(p_id uuid, p_name text, p_relationship text, p_phone text) returns uuid` (`p_id` null = สร้าง)
  - `delete_my_relative(p_id uuid) returns void`
  - คอลัมน์ `caregivers.added_by_patient boolean not null default false`
- ทั้งสามเป็น `security definer set search_path = public`, `revoke … from public, anon`, `grant … to authenticated`; เขียน `audit_logs` (actions `save_relative` / `delete_relative`, `table_name = 'caregivers'`, `row_id` = id ญาติ) ตามรูปแบบ `save_my_profile`

- [ ] **Step 1: เขียน `92_relatives.sql` ให้ล้ม** ผู้ใช้: AD admin, PU ผู้ป่วยของ P1, PW ผู้ป่วยของ P3, CG ผู้ดูแลที่มีบัญชี (caregivers.user_id = CG, phone `0899990001`), DO doctor. กรณีที่ต้องมี (assert ทุกข้อ):
  - PU สร้างญาติ `('ก', 'ลูก', '0899990001')` ได้ id; แถว `caregivers` ใหม่ `user_id is null and added_by_patient`; ลิงก์ `confirmed`, `can_manage_plan = false`; **ไม่ใช่ id ของแถว CG** (Review Focus 1); CG เรียก `can_see_patient(P1)` ต้องเป็นเท็จ
  - `list_my_relatives()` ของ PU เห็นญาตินั้นพร้อม `editable = true` และเห็นญาติที่ AD สร้าง (`insert caregivers` ปกติ + `patient_caregivers`) พร้อม `editable = false`; PW เห็นรายการว่าง
  - แก้ด้วย `p_id` เปลี่ยนชื่อ/ความสัมพันธ์/เบอร์ได้; แก้ id ของ AD → 42501; แก้ id ของผู้ป่วยอื่น → 42501
  - ถ้า AD ผูกญาติของ PU กับผู้ป่วย P3 ด้วย → `editable` ของ PU เป็นเท็จ และ `delete_my_relative` โดย PU → 42501
  - ลบสำเร็จ: ลิงก์หาย แถว `caregivers` หายเมื่อไม่เหลือการผูกอื่น; ลบ id ของ AD → 42501
  - ค่าที่ผิดแต่ละแบบ 22023 และจำนวนแถวไม่เปลี่ยน: ชื่อ `''`, `'   '`, `repeat('ก',101)`; ความสัมพันธ์ `repeat('ก',51)`; เบอร์ `''`, `repeat('1',21)`; คนที่ 21 (วนสร้าง 20 แล้วสร้างอีก 1); ขอบเขต 100/50/20 ผ่าน
  - ผู้เรียก 42501: AD, DO, CG, ผู้ใช้ไม่ล็อกอิน (`request.jwt.claims` ว่าง), ผู้ป่วยที่ถูกปิดบัญชี (`profiles.is_active = false`)
  - audit: หลังสร้างมีแถว `audit_logs` ที่ `action = 'save_relative'` และ `actor` เป็น PU หนึ่งแถว
- [ ] **Step 2: รัน `pnpm test:sql` ในรีโปเว็บ ยืนยันล้ม** (ไม่มีฟังก์ชัน)
- [ ] **Step 3: เขียนหัวข้อ `-- 18)`** ตาม Interfaces + Global Constraints; ใช้ `add column if not exists`, `create or replace function`; หาผู้ป่วยด้วยแถว `patients where user_id = auth.uid()` (เลือกแถวเดียวตาม `order by id limit 1` เหมือน `claim_my_patient`); ใช้ advisory lock ต่อผู้ป่วยตอนสร้างเพื่อกันกดซ้ำชนเพดาน 20
- [ ] **Step 4: รัน `pnpm test:sql` ให้ผ่านทุกไฟล์ (ไฟล์เดิมไม่ถูกกระทบ)**
- [ ] **Step 5: Commit (รีโปเว็บ)** `git add supabase/integration.sql supabase/tests/92_relatives.sql` → `feat(db): patient-managed relatives (list/save/delete_my_relative)`

---

### Task 2: แอป — โมเดล `Relative` + `AppState.applyRelatives`

**Files:**
- Modify: `caredose_app/lib/models/models.dart` (`Relative`), `caredose_app/lib/state/app_state.dart`
- Test: `caredose_app/test/models_test.dart`, `caredose_app/test/app_state_test.dart`

**Interfaces:**
- Produces:
  - `Relative({required String id, required String name, String rel = '', String phone = '', bool editable = true})`; `fromJson`/`toJson` มี `editable` (ข้อมูลเก่าที่ไม่มีคีย์ = `true`)
  - `factory Relative.fromServer(Json j)` อ่านคีย์ `id`, `name`, `relationship`→`rel`, `phone`, `editable`
  - `AppState.applyRelatives(List<Relative> server)` ตั้ง `data.relatives = server` แล้ว `_commit` เฉพาะเมื่อผลต่างจากเดิม (เหมือน `applyRemote`)

- [ ] **Step 1: เขียนเทสต์ให้ล้ม** `models_test`: `fromJson` ของข้อมูลเก่า (ไม่มี `editable`) ได้ `true`; `toJson`→`fromJson` วนกลับได้; `fromServer` แปลงคีย์ `relationship` `app_state_test`: `applyRelatives` ทับรายการในเครื่องทั้งหมดด้วยรายการของเซิร์ฟเวอร์ (รวม `editable: false`); เรียกซ้ำด้วยรายการเดิมไม่ทำให้ `notifyListeners` ซ้ำ (นับจำนวนครั้ง)
- [ ] **Step 2: รันเทสต์สองไฟล์ ยืนยันล้ม**
- [ ] **Step 3: เขียนโค้ดตาม Interfaces**
- [ ] **Step 4: `flutter test test/models_test.dart test/app_state_test.dart` ผ่าน และ `flutter analyze` สะอาด**
- [ ] **Step 5: Commit (รีโปแอป)** `feat(app): relative model carries editable; apply server list`

---

### Task 3: แอป — `RelativeRepository`, `RelativeSync` และตัวจริงของ Supabase

**Files:**
- Create: `lib/services/relative_repository.dart`, `lib/services/relative_sync.dart`, `lib/services/supabase_relative_repository.dart`
- Create (test): `test/fake_relative_repository.dart`, `test/relative_sync_test.dart`

**Interfaces:**
- Consumes: `Relative`, `AppState.applyRelatives`, `AppState.saveRelative`, `AppState.deleteRelative`, `guardCall` (จาก `supabase_auth_repository.dart`), `AuthFailure`
- Produces:
  - `abstract class RelativeRepository { Future<List<Relative>> fetch(); Future<String> save({String? id, required String name, required String rel, required String phone}); Future<void> delete(String id); }` โยนเฉพาะ `AuthFailure`
  - `SupabaseRelativeRepository(SupabaseClient)` เรียก RPC สามตัวของ Task 1 (`p_relationship` ← `rel`) ทุกเมธอดห่อด้วย `guardCall`
  - `class RelativeSync { RelativeSync(RelativeRepository repo, AppState state, {bool Function()? canPull}); Future<void> pull(); Future<void> save({String? id, required String name, required String rel, required String phone}); Future<void> delete(String id); }`
    - `pull()` ไม่โยนข้อผิดพลาด; ถ้ากำลังดึงอยู่หรือ `canPull()` เท็จ ไม่ทำอะไร
    - `save`/`delete` โยน `AuthFailure` เมื่อเซิร์ฟเวอร์ล้ม และ **ไม่แก้สำเนา**; สำเร็จแล้วอัปเดตสำเนา (`saveRelative` ด้วย id ที่เซิร์ฟเวอร์ตอบ / `deleteRelative`)
    - **ตัวนับเวอร์ชัน**: `save`/`delete` เพิ่มตัวนับ; `pull()` จดตัวนับก่อน `fetch()` และทิ้งผลถ้าเปลี่ยนระหว่างรอ (Review Focus 4)

- [ ] **Step 1: เขียน `FakeRelativeRepository`** (รายการในหน่วยความจำ, `failure` ตั้งให้โยน `AuthFailure(AuthFailureKind.network)`, ตัวนับการเรียก, `gate` Completer ให้ค้าง `fetch`)
- [ ] **Step 2: เขียน `relative_sync_test.dart` ให้ล้ม** (ใช้ `AppState` จริงตาม `app_state_test.dart`): pull ทับสำเนาด้วยรายการเซิร์ฟเวอร์ (รวม `editable: false`); pull ที่ `fetch` ล้มไม่แก้สำเนา ไม่โยน; save สำเร็จ → สำเนามีญาติ id จากเซิร์ฟเวอร์; save ล้ม → โยน `AuthFailure` และสำเนาเท่าเดิม; delete ล้ม → สำเนาเท่าเดิม; ค้าง `fetch` ด้วย `gate` แล้ว `save` เสร็จ จากนั้นปล่อย `gate` → สำเนายังมีผลของ `save`; `canPull` เท็จ → ไม่เรียก `fetch`
- [ ] **Step 3: รันยืนยันล้ม**
- [ ] **Step 4: เขียนโค้ดสามไฟล์ตาม Interfaces** (ตัวจริงของ Supabase เป็นตัวห่อบางๆ ไม่มีเทสต์หน่วย เหมือน `SupabaseMedRepository`)
- [ ] **Step 5: `flutter test test/relative_sync_test.dart` ผ่าน; `flutter analyze` สะอาด**
- [ ] **Step 6: Commit (รีโปแอป)** `feat(app): relatives repository and sync with the server`

---

### Task 4: แอป — หน้าญาติเรียกซิงก์, ผูกใน main, แสดงเฉพาะที่แก้ได้

**Files:**
- Modify: `lib/widgets/person_form.dart`, `lib/screens/contacts_screen.dart`, `lib/main.dart`, `test/helpers.dart`
- Test: `test/contacts_screen_test.dart` (+ ปรับเทสต์ที่ใช้ `PersonForm` เดิมถ้ามี)

**Interfaces:**
- Consumes: `RelativeSync`, `FakeRelativeRepository` (Task 3), `Relative.editable`
- Produces:
  - `PersonForm.onSave` เปลี่ยนเป็น `Future<String?> Function(Map<String, String> v)` (คืนข้อความผิดพลาดหรือ `null` เมื่อสำเร็จ) และ `onDelete` เป็น `Future<String?> Function()?`; ฟอร์มปิดปุ่มและแสดงสถานะรอระหว่างรอ แสดงข้อความผิดพลาดใน `ErrorBox` แทนการปิดฟอร์ม
  - `main.dart`: สร้าง `RelativeSync(SupabaseRelativeRepository(Supabase.instance.client), state, canPull: () => auth.status == AuthStatus.ready)`, ส่ง `onPulled: relativeSync.pull` ให้ `MedSync`, เพิ่ม `Provider<RelativeSync>.value`
  - `helpers.dart` `pumpApp`: เพิ่ม `lastRelativeRepo` (`FakeRelativeRepository`) และ `Provider<RelativeSync>` ตามแบบ `NoticeSync`

- [ ] **Step 1: เขียน/ปรับเทสต์ให้ล้ม** `contacts_screen_test`: เพิ่มญาติผ่านฟอร์ม → `lastRelativeRepo` ได้รับ `save` และการ์ดขึ้นในรายการ; เซิร์ฟเวอร์ล้ม (`failure` ตั้งไว้) → ฟอร์มยังเปิด แสดง 'ไม่มีอินเทอร์เน็ต กรุณาลองใหม่' และรายการไม่เปลี่ยน; ญาติ `editable: false` แสดงชื่อ/เบอร์/ปุ่ม 'โทรหาญาติ' แต่ไม่มีปุ่ม 'แก้ไข'; ลบญาติ → เรียก `delete` ที่เก็บปลอม; ฟอร์มยังกันชื่อ/เบอร์ว่างด้วยข้อความเดิม 'กรุณากรอกชื่อและเบอร์โทร'; เบอร์ยาวเกิน 20 หรือชื่อเกิน 100 ได้ข้อความตรวจฝั่งแอปก่อนเรียกเซิร์ฟเวอร์ (ใช้ข้อความ 'ชื่อต้องไม่เกิน 100 ตัวอักษร' / 'เบอร์โทรต้องไม่เกิน 20 ตัว')
- [ ] **Step 2: รันยืนยันล้ม**
- [ ] **Step 3: แก้ `PersonForm`, `_openRelative`, ปุ่มแก้ไขตาม `editable`, `main.dart`, `helpers.dart`**
- [ ] **Step 4: `flutter test` ทั้งชุดผ่าน; `flutter analyze` สะอาด**
- [ ] **Step 5: Commit (รีโปแอป)** `feat(app): add, edit and delete relatives through the server`

---

### Task 5: ทดสอบมือและตรวจทั้ง branch

- [ ] **Step 1: ให้ผู้ใช้รันสคริปต์ `integration.sql` ใหม่ทั้งไฟล์ใน Supabase SQL Editor** แล้วรันคิวรียืนยัน: `select proname from pg_proc where proname in ('list_my_relatives','save_my_relative','delete_my_relative');` ต้องได้ 3 แถว และ `select column_name from information_schema.columns where table_name='caregivers' and column_name='added_by_patient';` ต้องได้ 1 แถว
- [ ] **Step 2: ทดสอบมือ** เพิ่มญาติในแอป → เห็นในเว็บทั้ง "ญาติและผู้ดูแล" และหน้าข้อมูลผู้ป่วย; เพิ่มญาติจากหน้า "ญาติและผู้ดูแล" ของเว็บแล้วผูกผู้ป่วย → เห็นในแอป (หลังกลับเข้าแอปหรือรอ 5 นาที) โดยไม่มีปุ่มแก้; ถอนแอปลงใหม่/ล็อกอินใหม่ → รายชื่อกลับมา
- [ ] **Step 3: ให้ผู้ตรวจ (fresh reviewer) ตรวจทั้งสอง branch เทียบกับสเปก** รายงานสิ่งที่ตรวจแล้วและไม่ได้ตรวจ; ถามผู้ใช้ก่อน push หรือ merge
