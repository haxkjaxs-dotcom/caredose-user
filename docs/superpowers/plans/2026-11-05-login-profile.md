# CareDose Login + Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** เปิดแอปครั้งแรกต้องเข้าสู่ระบบด้วยเบอร์มือถือไทย + OTP จริง (Supabase) แล้วกรอกชื่อเล่น/ชื่อ-นามสกุลจริง/อายุ/โรคประจำตัว ก่อนเข้าแอปเดิม

**Architecture:** ตรรกะบริสุทธิ์ (`auth_validators`, `Profile`, `mapAuthError`) แยกจาก UI; `AuthRepository` (interface) มี implementation จริงด้วย `supabase_flutter`; `AuthState` (ChangeNotifier) ถือสถานะ `loading|loggedOut|needsProfile|ready|unavailable` และแคชโปรไฟล์; `AuthGate` เลือกหน้า; ฝั่ง Supabase มีตาราง `profiles` + RLS

**Tech Stack:** Flutter (ที่มีอยู่ใน `caredose_app/`), `supabase_flutter`, `provider`, `shared_preferences`, Supabase MCP tools (สร้างโปรเจกต์/migration)

**Spec:** `docs/superpowers/specs/2026-11-05-login-profile-design.md` (ต่อยอด `2026-11-04-caredose-flutter-design.md`)

## Global Constraints

- รันคำสั่ง Flutter จาก `caredose_app/`; แก้เฉพาะ `caredose_app/` และ `docs/` ห้ามแตะ `src/` (เว็บ React)
- เบอร์: รับ `0XXXXXXXXX` 10 หลักขึ้นต้น 06/08/09 ตัดช่องว่างและขีด แปลงเป็น `+66XXXXXXXXX`
- OTP 6 หลักตัวเลข; ปุ่ม `ส่งรหัสอีกครั้ง` ใช้ได้หลังรอ 60 วินาที
- โปรไฟล์: ชื่อเล่น 1–50, ชื่อ-นามสกุลจริง 1–100, อายุ 1–120 (จำนวนเต็ม), โรคประจำตัวอย่างน้อยหนึ่งอย่าง (`ไม่มีโรคประจำตัว` ไม่ใช้ร่วมกับอื่น), ต้องติ๊กยินยอมก่อนบันทึก; ไม่เก็บฟิลด์อื่น
- ข้อความ error ตามที่ระบุในแต่ละ task (คัดลอกตรงตัวจาก spec)
- Supabase: โปรเจกต์ชื่อ `caredose` ภูมิภาค `ap-southeast-1`; ตาราง `profiles` + RLS ตาม SQL ใน spec; ไม่มี policy delete; คีย์ฝั่งแอปใช้เฉพาะ publishable key
- ออกจากระบบ = sign out + ล้างแคชโปรไฟล์ + `AppState.resetAll()`
- ผู้ใช้ต้องตั้งค่า Phone provider และเบอร์ทดสอบเองในแดชบอร์ด Supabase (เครื่องมือตั้งค่า Auth ไม่ได้)
- ทุก commit ลงท้ายด้วย `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`

## Review Focus

1. ปิดแอประหว่างยืนยัน OTP แล้วกับกรอกโปรไฟล์ → เปิดใหม่ต้องเข้าหน้ากรอกโปรไฟล์ (ไม่ใช่หน้าหลัก/หน้าล็อกอิน) (Task 3)
2. เบอร์พิมพ์รูปแบบอื่น `+66 81-234-5678`, `66812345678` → ยอมรับ ส่วน `0212345678`, `081234567`, ว่าง → ปฏิเสธ (Task 1)
3. กดปุ่มส่งรหัส/ยืนยันซ้ำเร็ว ๆ → ส่งคำขอครั้งเดียว (Task 4, 5)
4. ออกจากระบบตอนไม่มีเน็ต/โยนข้อผิดพลาด → ยังล้างข้อมูลในเครื่องและกลับหน้าล็อกอิน (Task 3)
5. บันทึกโปรไฟล์ไม่สำเร็จ (ไม่มีเน็ต) → แสดง error และข้อมูลที่กรอกยังอยู่ (Task 5)

---

### Task 1: ตรรกะบริสุทธิ์ — validators และ Profile

**Files:**
- Create: `caredose_app/lib/models/profile.dart`, `caredose_app/lib/logic/auth_validators.dart`
- Test: `caredose_app/test/auth_validators_test.dart`, `caredose_app/test/profile_test.dart`

**Interfaces:**
- Produces:
  - `class Profile { final String nickname, fullName; final int age; final List<String> conditions; final DateTime consentAt; Json toJson(); factory Profile.fromJson(Map<String, dynamic>) }` — คีย์ JSON ตรงกับคอลัมน์: `nickname`, `full_name`, `age`, `conditions`, `consent_at` (ISO-8601); `fromJson` โยน `FormatException` เมื่อฟิลด์จำเป็นขาด/ผิดชนิด
  - `String? normalizeThaiMobile(String raw)` → `+66…` หรือ `null`
  - `String displayPhone(String e164)` → `0…` (`+66812345678` → `0812345678`)
  - `const commonConditions = ['ความดันโลหิตสูง','เบาหวาน','โรคหัวใจ','ไขมันในเลือดสูง','โรคไต','หอบหืด']`, `const noConditions = 'ไม่มีโรคประจำตัว'`
  - `List<String> parseConditions(String custom)` — แยกด้วย `,`/`，`, trim, ตัดว่าง, ตัดซ้ำคงลำดับ
  - `String? validateProfile({required String nickname, required String fullName, required String ageText, required List<String> conditions, required bool consent})` → ข้อความ error แรกที่เจอหรือ `null`; ลำดับตรวจ: ชื่อเล่น → ชื่อจริง → อายุ → โรค → ยินยอม; ข้อความ: `กรุณากรอกชื่อเล่น`, `กรุณากรอกชื่อ-นามสกุลจริง`, `กรุณากรอกอายุ 1–120 ปี`, `กรุณาเลือกโรคประจำตัวหรือเลือกไม่มี`, `กรุณายินยอมให้เก็บข้อมูลสุขภาพก่อนบันทึก`; ค่าที่มีแต่ช่องว่างนับเป็นว่าง; ชื่อเกินความยาวสูงสุดเป็น error เดียวกับว่าง

- [ ] **Step 1: เขียน test ที่ fail**
  - `normalizeThaiMobile`: `'0812345678'`, `'081-234-5678'`, `'081 234 5678'`, `'+66 81-234-5678'`, `'66812345678'` → `'+66812345678'`; `'0912345678'` → `'+66912345678'`; `'0612345678'` → `'+66612345678'`; `'0212345678'`, `'081234567'`, `'08123456789'`, `'12345'`, `''`, `'abc'` → `null` (**Review Focus 2**)
  - `displayPhone('+66812345678') == '0812345678'`
  - `parseConditions(' โรคกระเพาะ, ภูมิแพ้，โรคกระเพาะ,, ')` → `['โรคกระเพาะ','ภูมิแพ้']`
  - `validateProfile`: ครบถูกต้อง → `null`; ชื่อเล่น `'  '` → `กรุณากรอกชื่อเล่น`; ชื่อจริงว่าง; อายุ `''`,`'0'`,`'121'`,`'25.5'`,`'abc'` → `กรุณากรอกอายุ 1–120 ปี`; อายุ `'1'` และ `'120'` ผ่าน; `conditions: []` → `กรุณาเลือกโรคประจำตัวหรือเลือกไม่มี`; `consent: false` → ข้อความยินยอม; ชื่อเล่น 51 ตัวอักษร → `กรุณากรอกชื่อเล่น`
  - `Profile`: `fromJson(toJson())` เท่าเดิม; `toJson()['full_name']`; `fromJson({})` โยน `FormatException`
- [ ] **Step 2:** รัน `flutter test test/auth_validators_test.dart test/profile_test.dart` → FAIL (ไม่มีไฟล์/ฟังก์ชัน)
- [ ] **Step 3:** implement ตาม Interfaces (เบอร์: ตัดทุกตัวที่ไม่ใช่ตัวเลขและ `+`, ถ้าขึ้นต้น `+66`/`66` ให้เปลี่ยนเป็น `0`, แล้วตรวจ regex `^0[689]\d{8}$`)
- [ ] **Step 4:** รันเทสต์ → PASS; `flutter analyze` → No issues
- [ ] **Step 5:** commit `feat: add phone/profile validators and Profile model`

### Task 2: Backend — โปรเจกต์ Supabase + ตาราง profiles + config (ต้องขอยืนยันผู้ใช้)

**Files:**
- Create: `caredose_app/lib/config.dart`

**Interfaces:**
- Produces: `const supabaseUrl = '<url>'`, `const supabasePublishableKey = '<key>'` ใน `lib/config.dart`

- [ ] **Step 1 (หยุดถามผู้ใช้):** แจ้งว่าจะสร้างโปรเจกต์ Supabase `caredose` (org `qfbfroeibmotpupavfpa`, ภูมิภาค `ap-southeast-1`) แสดงค่าใช้จ่ายที่ได้จาก Supabase MCP (ตรวจ cost ก่อน) รอผู้ใช้ยืนยัน; ถ้าไม่ยืนยัน หยุดงานทั้งแผน
- [ ] **Step 2:** สร้างโปรเจกต์ด้วย `create_project` แล้วรอจนสถานะ `ACTIVE_HEALTHY` (ตรวจด้วย `get_project`)
- [ ] **Step 3:** `apply_migration` ชื่อ `create_profiles` ด้วย SQL จาก spec (ตาราง `profiles` + เปิด RLS + 3 policy select/insert/update)
- [ ] **Step 4:** ตรวจด้วย `execute_sql`: `select policyname, cmd from pg_policies where tablename = 'profiles'` → มี 3 policy (SELECT, INSERT, UPDATE) ไม่มี DELETE และ `select relrowsecurity from pg_class where oid = 'public.profiles'::regclass` → `true`; ลองสลับ role: ในหนึ่งคำสั่ง `begin; … set local role authenticated; set local request.jwt.claims = '{"sub":"<uuid A>"}'; select count(*) …; rollback;` เพื่อยืนยันว่าผู้ใช้ A มองเห็นแถวของ B = 0 (ถ้าเครื่องมือไม่รองรับธุรกรรมหลายคำสั่ง ให้บันทึกว่าข้ามและพึ่งการตรวจ policy)
- [ ] **Step 5:** `get_advisors` (security) → ไม่มี finding ระดับ ERROR/WARN เกี่ยวกับ `profiles`; ถ้ามี แก้ด้วย migration
- [ ] **Step 6:** `get_project_url` + `get_publishable_keys` → เขียน `lib/config.dart` (ค่าสาธารณะ ใส่ใน repo ได้); ห้ามใส่ `service_role`/secret key ที่ใดเลย
- [ ] **Step 7:** commit `feat: add supabase config`
- [ ] **Step 8 (หยุดแจ้งผู้ใช้):** ให้ขั้นตอนทำเองในแดชบอร์ด: Authentication → Sign In / Providers → เปิด **Phone**; เลื่อนลงที่ Test Phone Numbers and OTPs ใส่ `66812345678=123456`; แล้วบอกให้ผู้ใช้ตอบกลับเมื่อเสร็จ (ไม่ต้องรอก่อนทำ Task 3–5 แต่ต้องเสร็จก่อน Task 7)

### Task 3: AuthRepository, AuthState และ Supabase implementation

**Files:**
- Create: `caredose_app/lib/services/auth_repository.dart`, `caredose_app/lib/services/supabase_auth_repository.dart`, `caredose_app/lib/state/auth_state.dart`
- Modify: `caredose_app/pubspec.yaml` (`flutter pub add supabase_flutter`)
- Test: `caredose_app/test/auth_state_test.dart`, `caredose_app/test/auth_failure_test.dart`, `caredose_app/test/fake_auth_repository.dart` (helper)

**Interfaces:**
- Consumes: `Profile` (Task 1)
- Produces:
  - `enum AuthFailureKind { invalidCode, rateLimited, network, unknown }`
  - `class AuthFailure implements Exception { const AuthFailure(this.kind); final AuthFailureKind kind; String get message; }` — `invalidCode`→`รหัส OTP ไม่ถูกต้องหรือหมดอายุ`, `rateLimited`→`ขอรหัสบ่อยเกินไป กรุณารอสักครู่`, `network`→`ไม่มีอินเทอร์เน็ต กรุณาลองใหม่`, `unknown`→`เกิดข้อผิดพลาด กรุณาลองใหม่`
  - `abstract class AuthRepository { bool get isSignedIn; String? get phone; Future<void> sendOtp(String e164); Future<void> verifyOtp(String e164, String code); Future<Profile?> loadProfile(); Future<void> saveProfile(Profile p); Future<void> signOut(); }` — ทุกเมธอดโยนเฉพาะ `AuthFailure`
  - `AuthFailure mapAuthError(Object e)` (ใน `supabase_auth_repository.dart`) — `AuthApiException` ที่ `code` เป็น `otp_expired`/`otp_disabled`/`validation_failed` หรือข้อความมี `Token has expired or is invalid` → `invalidCode`; `over_sms_send_rate_limit`/`over_request_rate_limit` หรือ `statusCode == '429'` → `rateLimited`; `SocketException`, `TimeoutException`, `AuthRetryableFetchException`, `http.ClientException` → `network`; อื่น ๆ → `unknown`; `AuthFailure` ที่ส่งเข้ามาคืนตัวเดิม
  - `class SupabaseAuthRepository implements AuthRepository { SupabaseAuthRepository(SupabaseClient c); }` — `signInWithOtp(phone: e164)`, `verifyOTP(phone:, token:, type: OtpType.sms)`, อ่าน/เขียน `profiles` ด้วย `id = auth.uid`, `saveProfile` ใช้ `upsert` พร้อม `updated_at`; ทุกเมธอดห่อ `try/catch` แล้ว `throw mapAuthError(e)`
  - `enum AuthStatus { loading, loggedOut, needsProfile, ready, unavailable }`
  - `class AuthState extends ChangeNotifier { AuthState(AuthRepository repo, SharedPreferences prefs, {void Function(Profile p, String phoneE164)? onSignedIn, VoidCallback? onSignedOut}); AuthStatus status; Profile? profile; String? get phoneE164; Future<void> init(); Future<void> sendOtp(String e164); Future<void> verifyOtp(String e164, String code); Future<void> saveProfile(Profile p); Future<void> signOut(); }`
    - `init`: ไม่ signed in → `loggedOut`; signed in → `loadProfile()`: มีโปรไฟล์ → แคช (`caredose_profile`) + `ready`; `null` → `needsProfile`; โยน `AuthFailure` → ถ้ามีแคชใช้แคช `ready` ไม่มีแคช `unavailable`
    - `verifyOtp` สำเร็จ → `loadProfile()`: มี → `ready` + แคช + `onSignedIn`; ไม่มี → `needsProfile`
    - `saveProfile` สำเร็จ → แคช + `ready` + `onSignedIn(profile, phone)`; ล้มเหลวโยน `AuthFailure` ต่อ ไม่เปลี่ยนสถานะ
    - `signOut`: เรียก `repo.signOut()` แต่ไม่ว่าจะสำเร็จหรือโยน ต้องลบแคช, ตั้ง `loggedOut`, เรียก `onSignedOut` (ไม่โยนต่อ)
  - helper test `FakeAuthRepository` (ใน `test/fake_auth_repository.dart`): ฟิลด์ปรับได้ `signedIn`, `phoneValue`, `stored` (Profile?), `failure` (AuthFailure? ที่ทุกเมธอดโยน), `sendCalls`, `verifyCalls`, `saveCalls`, `Completer? gate` ที่ถ้ามีจะทำให้ `sendOtp`/`verifyOtp`/`saveProfile` รอ

- [ ] **Step 1: เขียน test ที่ fail**
  - `mapAuthError`: `AuthApiException('Token has expired or is invalid', statusCode: '403', code: 'otp_expired')` → `invalidCode`; `code: 'over_sms_send_rate_limit'` → `rateLimited`; `SocketException('x')` → `network`; `StateError('x')` → `unknown`; `AuthFailure(AuthFailureKind.network)` คืนตัวเดิม; `AuthFailure.message` ทั้ง 4 ข้อความ (ตรวจ constructor ของ `AuthApiException` ตามเวอร์ชันที่ติดตั้ง)
  - `AuthState`: ไม่ signed in → `loggedOut`; signed in + โปรไฟล์ → `ready` และ `prefs` มี `caredose_profile`; signed in ไม่มีโปรไฟล์ → `needsProfile` (**Review Focus 1**: สร้าง `AuthState` ใหม่ด้วย repo เดิมหลังตั้ง `signedIn=true` + `stored=null` → `needsProfile`, ไม่ใช่ `loggedOut`/`ready`); signed in + `failure=network` + มีแคช → `ready` จากแคช; ไม่มีแคช → `unavailable`; `verifyOtp` ที่มีโปรไฟล์ → `ready` และ `onSignedIn` ถูกเรียกครั้งเดียวด้วยโปรไฟล์/เบอร์ที่ถูก; `verifyOtp` ผิด (`failure=invalidCode`) โยน `AuthFailure` และสถานะไม่เปลี่ยน; `saveProfile` สำเร็จ → `ready` + แคช + `onSignedIn`; `saveProfile` ล้มเหลว → โยน สถานะ `needsProfile` เดิม
  - **Review Focus 4:** `signOut` เมื่อ `failure=network` → ไม่โยน, `status == loggedOut`, แคชถูกลบ, `onSignedOut` ถูกเรียก
- [ ] **Step 2:** รัน `flutter test test/auth_failure_test.dart test/auth_state_test.dart` → FAIL
- [ ] **Step 3:** `flutter pub add supabase_flutter`; implement ไฟล์ทั้ง 3 ตาม Interfaces (`AuthState.profile` เก็บคู่กับ `phoneE164` จาก `repo.phone`)
- [ ] **Step 4:** รันเทสต์ทั้งหมด `flutter test` → PASS; `flutter analyze` → No issues
- [ ] **Step 5:** commit `feat: add auth repository, supabase implementation and AuthState`

### Task 4: หน้ากรอกเบอร์และหน้า OTP

**Files:**
- Create: `caredose_app/lib/screens/login_screen.dart`, `caredose_app/lib/screens/otp_screen.dart`
- Test: `caredose_app/test/login_screens_test.dart`

**Interfaces:**
- Consumes: `AuthState.sendOtp/verifyOtp`, `AuthFailure.message`, `normalizeThaiMobile`, `displayPhone` (Task 1, 3); widgets `AppCard`, `ErrorBox`, `LabeledField` จาก `lib/widgets/common.dart`
- Produces:
  - `class LoginScreen extends StatefulWidget { const LoginScreen({required this.onCodeSent}); final ValueChanged<String> onCodeSent; }` — เบอร์ผิด → `กรุณากรอกเบอร์มือถือ 10 หลักให้ถูกต้อง`; ปุ่ม `ส่งรหัส OTP` ปิดขณะรอผล; ผลสำเร็จเรียก `onCodeSent(e164)`; `AuthFailure` แสดง `.message` ใน `ErrorBox`
  - `class OtpScreen extends StatefulWidget { const OtpScreen({required this.phoneE164, required this.onChangePhone}); }` — ข้อความ `ส่งรหัส OTP ไปยัง 0XXXXXXXXX แล้ว`; ช่อง `ValueKey('otp')` 6 หลักตัวเลขเท่านั้น; ปุ่ม `ยืนยัน` (ปิดขณะรอ); รหัสไม่ครบ → `กรุณากรอกรหัส OTP 6 หลัก`; ปุ่ม `ส่งรหัสอีกครั้ง` ปิดและแสดงนับถอยหลัง `ส่งรหัสอีกครั้งใน N วินาที` 60→0 ด้วย `Timer.periodic`; ปุ่ม `เปลี่ยนเบอร์` เรียก `onChangePhone`; ยกเลิก timer ใน `dispose`
  - ช่องเบอร์ใน `LoginScreen` มี `ValueKey('phone')`

- [ ] **Step 1: เขียน test ที่ fail** (ห่อด้วย `ChangeNotifierProvider<AuthState>` + `FakeAuthRepository`)
  - login: ป้อน `'12345'` กด `ส่งรหัส OTP` → เห็นข้อความเบอร์ผิดและ `sendCalls == 0`; ป้อน `'081-234-5678'` → `sendCalls == 1` และ `onCodeSent('+66812345678')`; `failure=rateLimited` → เห็น `ขอรหัสบ่อยเกินไป กรุณารอสักครู่`
  - **Review Focus 3 (login):** ตั้ง `gate` ค้าง, กดปุ่มสองครั้งติดกัน → `sendCalls == 1`
  - otp: เห็น `ส่งรหัส OTP ไปยัง 0812345678 แล้ว`; ป้อน `'12'` กด `ยืนยัน` → `กรุณากรอกรหัส OTP 6 หลัก`; `failure=invalidCode` + `'123456'` → `รหัส OTP ไม่ถูกต้องหรือหมดอายุ`; ปุ่ม `ส่งรหัสอีกครั้ง` ปิดทันที, หลัง `tester.pump(Duration(seconds: 60))` เปิดและกดแล้ว `sendCalls` เพิ่ม; **Review Focus 3 (otp):** กด `ยืนยัน` สองครั้งขณะ `gate` ค้าง → `verifyCalls == 1`
- [ ] **Step 2:** รัน `flutter test test/login_screens_test.dart` → FAIL
- [ ] **Step 3:** implement ทั้งสองหน้า (กฎ busy: ตั้งธง `busy` ก่อน `await` และตรวจก่อนเริ่ม)
- [ ] **Step 4:** รัน `flutter test` ทั้งหมด → PASS; `flutter analyze` → No issues
- [ ] **Step 5:** commit `feat: add phone login and OTP screens`

### Task 5: หน้ากรอกข้อมูลส่วนตัว

**Files:**
- Create: `caredose_app/lib/screens/profile_screen.dart`
- Test: `caredose_app/test/profile_screen_test.dart`

**Interfaces:**
- Consumes: `validateProfile`, `parseConditions`, `commonConditions`, `noConditions` (Task 1); `AuthState.saveProfile`; `Profile`
- Produces: `class ProfileScreen extends StatefulWidget { const ProfileScreen(); }` — ช่อง: ชื่อเล่น, ชื่อ-นามสกุลจริง, อายุ (`TextInputType.number`), `FilterChip` ต่อโรคใน `commonConditions` + `ไม่มีโรคประจำตัว`, ช่องพิมพ์โรคอื่น (`ValueKey('other-conditions')`), `CheckboxListTile` ข้อความ `ยินยอมให้เก็บข้อมูลสุขภาพของฉันไว้ในระบบ`, ปุ่ม `บันทึก` (ปิดจนติ๊กยินยอม และปิดขณะรอผล); เลือก `ไม่มีโรคประจำตัว` → ล้างโรคอื่นและช่องพิมพ์; เลือกโรคอื่น/พิมพ์ → เอา `ไม่มีโรคประจำตัว` ออก; เมื่อกดบันทึกใช้ `validateProfile` แสดงผลใน `ErrorBox`; ประกอบ `Profile(conditions: เลือก + parseConditions(ช่องพิมพ์), consentAt: DateTime.now())`; `AuthFailure` แสดง `.message` และคงข้อมูลที่กรอกไว้

- [ ] **Step 1: เขียน test ที่ fail**
  - ปุ่ม `บันทึก` ปิดจนติ๊กยินยอม แล้วเปิด
  - กรอกครบ (`สมศรี`, `สมศรี ใจดี`, `65`, เลือก `เบาหวาน` + พิมพ์ `ภูมิแพ้`) ติ๊ก กด → `saveCalls == 1` และโปรไฟล์ที่บันทึกมี `conditions == ['เบาหวาน','ภูมิแพ้']`, `age == 65`
  - อายุ `0` → `กรุณากรอกอายุ 1–120 ปี` และ `saveCalls == 0`; ไม่เลือกโรค → `กรุณาเลือกโรคประจำตัวหรือเลือกไม่มี`
  - เลือก `เบาหวาน` แล้วเลือก `ไม่มีโรคประจำตัว` → `เบาหวาน` ถูกล้าง; แล้วเลือก `โรคไต` → `ไม่มีโรคประจำตัว` ถูกเอาออก
  - **Review Focus 5:** `failure=network` → เห็น `ไม่มีอินเทอร์เน็ต กรุณาลองใหม่` และค่าในช่องชื่อเล่น/ชื่อจริง/อายุ/ตัวเลือกโรคยังอยู่ครบ
  - **Review Focus 3:** `gate` ค้าง กดบันทึกสองครั้ง → `saveCalls == 1`
- [ ] **Step 2:** รัน `flutter test test/profile_screen_test.dart` → FAIL
- [ ] **Step 3:** implement (ชื่อ/ข้อความในหน้าจอตาม spec; ห่อด้วย `SingleChildScrollView`; ตัวอักษร "ใหญ่มาก" ต้องไม่ overflow)
- [ ] **Step 4:** รัน `flutter test` ทั้งหมด → PASS; `flutter analyze` → No issues
- [ ] **Step 5:** commit `feat: add profile screen`

### Task 6: AuthGate, ต่อ main, แก้หน้าตั้งค่า และ INTERNET permission

**Files:**
- Create: `caredose_app/lib/auth_gate.dart`
- Modify: `caredose_app/lib/app.dart` (`home: AuthGate(child: _Shell())`), `caredose_app/lib/main.dart`, `caredose_app/lib/screens/settings_sheet.dart`, `caredose_app/android/app/src/main/AndroidManifest.xml`, `caredose_app/test/helpers.dart`, `caredose_app/test/settings_sheet_test.dart`
- Test: `caredose_app/test/auth_gate_test.dart`

**Interfaces:**
- Consumes: ทุกอย่างจาก Task 1–5; `AppState.setPatient`, `setVerifiedPhone`, `resetAll`
- Produces:
  - `class AuthGate extends StatelessWidget { const AuthGate({required this.child}); final Widget child; }` — `loading`→วงกลมโหลด; `unavailable`→ข้อความ `เชื่อมต่อไม่ได้ กรุณาลองใหม่` + ปุ่ม `ลองใหม่` (เรียก `AuthState.init`); `loggedOut`→ `LoginScreen` แล้ว `OtpScreen` (เก็บเบอร์ใน state ของ gate; `onChangePhone` กลับ `LoginScreen`); `needsProfile`→`ProfileScreen`; `ready`→`child`
  - `main.dart`: `await Supabase.initialize(url: supabaseUrl, anonKey: supabasePublishableKey)`; สร้าง `AuthState(SupabaseAuthRepository(Supabase.instance.client), prefs, onSignedIn: (p, phone) { appState.setPatient(p.nickname); appState.setVerifiedPhone(displayPhone(phone)); }, onSignedOut: appState.resetAll)`; เรียก `auth.init()` ก่อน `runApp`; เพิ่ม `ChangeNotifierProvider<AuthState>.value` ใน `MultiProvider`
  - `SettingsSheet`: เอาขั้นตอนเปลี่ยนเบอร์/OTP จำลอง (`changePhone`, `newPhone`, `otp`, `otpSent`, `otpError`, `_sendOtp`, `_verifyOtp`, `_cancelPhone`, ปุ่ม `เปลี่ยนเบอร์และยืนยัน OTP`) ออก; ข้อความใต้เบอร์เป็น `เบอร์ที่ใช้เข้าสู่ระบบ`; เพิ่มปุ่ม `ออกจากระบบ` (ใต้ปุ่มล้างข้อมูล) → กล่องยืนยัน `ออกจากระบบ? ข้อมูลยาและประวัติในเครื่องนี้จะถูกล้างด้วย` (ปุ่ม `ยกเลิก`/`ออกจากระบบ`) → `AuthState.signOut()` แล้ว `onClose()`; แก้ข้อความ `เกี่ยวกับแอป` เป็น `CareDose (ยาอุ่นใจ) ข้อมูลยาและประวัติการทานยาเก็บในเครื่องนี้ ส่วนข้อมูลส่วนตัวเก็บในระบบหลังเข้าสู่ระบบด้วยเบอร์โทร`
  - `helpers.dart`: `pumpApp` เพิ่ม `AuthState` ที่ `FakeAuthRepository(signedIn: true, stored: <Profile ตัวอย่าง>)` เรียก `init()` ให้ `ready` และใส่ใน `MultiProvider` เพื่อให้เทสต์เดิมผ่าน

- [ ] **Step 1: เขียน test ที่ fail**
  - `auth_gate_test.dart`: แต่ละสถานะแสดงหน้าถูก (`loggedOut`→เห็นปุ่ม `ส่งรหัส OTP`; ส่งสำเร็จ→เห็น `ส่งรหัส OTP ไปยัง`; `เปลี่ยนเบอร์` กลับหน้าเบอร์; `needsProfile`→เห็น `ยินยอมให้เก็บข้อมูลสุขภาพ`; `unavailable`→กด `ลองใหม่` แล้ว `init` ถูกเรียกอีก; `ready`→เห็นเนื้อหา child); ล็อกอินครบ flow ด้วย fake: verify สำเร็จ + `stored=null` → เห็นหน้าโปรไฟล์ → บันทึก → เห็น child และ `onSignedIn` ถูกเรียก
  - `settings_sheet_test.dart`: ลบเทสต์ `phone change validates phone and OTP before saving`; เพิ่ม `เบอร์ที่ยืนยันแสดงและไม่มีปุ่มเปลี่ยนเบอร์` (ไม่พบ `เปลี่ยนเบอร์และยืนยัน OTP`); `sign out asks for confirmation and clears local data` (ตั้ง `setPatient('คนอื่น')`, กดออกจากระบบ → เห็นกล่องยืนยัน → ยืนยัน → `AuthState.status == loggedOut` และ `AppState.data.patient == 'คุณแม่สมศรี'`); ยกเลิกกล่อง → ไม่เปลี่ยน
- [ ] **Step 2:** รัน `flutter test test/auth_gate_test.dart test/settings_sheet_test.dart` → FAIL
- [ ] **Step 3:** implement ตาม Interfaces; เพิ่ม `<uses-permission android:name="android.permission.INTERNET"/>` ใน `AndroidManifest.xml`
- [ ] **Step 4:** รัน `flutter test` ทั้งหมด → PASS (เทสต์เดิมทั้งหมดยังผ่าน); `flutter analyze` → No issues; `flutter build apk --debug` → Built
- [ ] **Step 5:** commit `feat: gate the app behind phone login and add sign out`

### Task 7: ตรวจรวมบน emulator ด้วยเบอร์ทดสอบ

- [ ] **Step 1:** ยืนยันว่าผู้ใช้ตั้งค่า Phone provider + เบอร์ทดสอบ `66812345678=123456` แล้ว (Task 2 ขั้น 8); ถ้ายัง หยุดถาม
- [ ] **Step 2:** `flutter analyze` → No issues; `flutter test` → All tests passed
- [ ] **Step 3:** รันบน emulator (`flutter run -d emulator-5554 --no-resident`) แล้วตรวจด้วย `adb`/ภาพหน้าจอ: กรอก `0812345678` → ส่งรหัส → กรอก `123456` → เห็นหน้าโปรไฟล์ → กรอกครบ ติ๊กยินยอม บันทึก → เห็นหน้าหลักและชื่อผู้ใช้เป็นชื่อเล่น; `adb shell am force-stop com.caredose.caredose` แล้วเปิดใหม่ → เข้าหน้าหลักทันที; ตั้งค่า → ออกจากระบบ → กลับหน้าเบอร์; กรอก OTP ผิด `000000` → เห็น `รหัส OTP ไม่ถูกต้องหรือหมดอายุ`
- [ ] **Step 4:** ตรวจในฐานข้อมูลด้วย `execute_sql`: `select nickname, age, conditions, consent_at is not null from profiles` → มีแถวของผู้ใช้ทดสอบ
- [ ] **Step 5:** รายงานผู้ใช้: สิ่งที่ตรวจได้จริง และสิ่งที่ยังไม่ได้ตรวจ (SMS จริง, iOS, release build); แจ้งว่าไม่ได้ push
