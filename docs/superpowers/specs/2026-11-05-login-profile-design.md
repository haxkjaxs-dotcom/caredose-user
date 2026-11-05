# CareDose — เข้าสู่ระบบด้วยเบอร์โทร (OTP) และกรอกข้อมูลส่วนตัว

วันที่: 2026-11-05 · ต่อยอดจาก `2026-11-04-caredose-flutter-design.md`

## เป้าหมาย

เปิดแอปครั้งแรกต้องเข้าสู่ระบบด้วยเบอร์โทรไทย ยืนยันเบอร์ด้วยรหัส OTP 6 หลักที่ส่งมาจริง แล้วกรอกข้อมูลส่วนตัว 3 อย่าง จากนั้นเข้าหน้าหลัก ครั้งต่อไปเข้าหน้าหลักทันที (จำ session)

## สิ่งที่เปลี่ยนจาก spec เดิม

- spec เดิมระบุ "ไม่มีบัญชีผู้ใช้ / SMS-OTP เป็นหน้าจอจำลอง" → ตอนนี้มีบัญชีผู้ใช้ (Supabase Auth) และ OTP เป็นของจริง
- หน้าตั้งค่า: เอาขั้นตอน "เปลี่ยนเบอร์ + OTP จำลอง" ออก, เบอร์ที่ยืนยันแสดงเป็นเบอร์ที่ล็อกอินจริง (อ่านอย่างเดียว), เพิ่มปุ่ม "ออกจากระบบ"
- ข้อความ "เกี่ยวกับแอป" ที่บอกว่าไม่มีระบบบัญชี ต้องแก้ให้ตรงความจริง

## ขอบเขต

รวม: หน้ากรอกเบอร์, หน้ากรอก OTP, หน้ากรอกข้อมูลส่วนตัว, การจำ session, ออกจากระบบ, โปรเจกต์ Supabase + ตาราง `profiles`

ไม่รวม: ซิงก์ข้อมูลยา/ประวัติ (ยังอยู่ในเครื่อง), เปลี่ยนเบอร์หลังล็อกอิน, ล็อกอินวิธีอื่น, การส่ง SMS จริงผ่านผู้ให้บริการ (ใช้เบอร์ทดสอบก่อน), หน้าแก้ไขข้อมูลส่วนตัวหลังบันทึกแล้ว

## ลำดับหน้าจอ

`AuthGate` ตัดสินหน้าตามสถานะ:

| สถานะ | หน้า |
|---|---|
| กำลังตรวจ session/โปรไฟล์ | หน้าโหลด |
| ยังไม่ล็อกอิน | หน้ากรอกเบอร์ → หน้ากรอก OTP |
| ล็อกอินแล้ว ยังไม่มีโปรไฟล์ | หน้ากรอกข้อมูลส่วนตัว |
| ล็อกอินแล้วและมีโปรไฟล์ | แอปเดิม (4 แท็บ) |

## หน้าจอและกฎ

**หน้ากรอกเบอร์:** ช่องเบอร์โทร รับ `0XXXXXXXXX` (10 หลัก ขึ้นต้น 06/08/09 ตามเบอร์มือถือไทย) ตัดช่องว่างและขีด แปลงเป็น `+66XXXXXXXXX` ก่อนส่ง; เบอร์ผิดรูปแบบ → `กรุณากรอกเบอร์มือถือ 10 หลักให้ถูกต้อง`; ปุ่ม `ส่งรหัส OTP`

**หน้ากรอก OTP:** แสดง `ส่งรหัส OTP ไปยัง 0XXXXXXXXX แล้ว`; ช่อง 6 หลัก (ตัวเลขเท่านั้น); ปุ่ม `ยืนยัน`; ปุ่ม `ส่งรหัสอีกครั้ง` ใช้ได้หลังรอ 60 วินาที (นับถอยหลังบนปุ่ม); ปุ่ม `เปลี่ยนเบอร์` กลับหน้าแรก; รหัสไม่ครบ 6 หลัก → `กรุณากรอกรหัส OTP 6 หลัก`

**หน้ากรอกข้อมูลส่วนตัว:** (รับเฉพาะ 4 ช่องนี้ ไม่เก็บอย่างอื่น)
- ชื่อเล่น (จำเป็น, 1–50 ตัวอักษร)
- ชื่อ-นามสกุลจริง (จำเป็น, 1–100 ตัวอักษร)
- อายุ (จำเป็น, จำนวนเต็ม 1–120)
- โรคประจำตัว: ปุ่มเลือกได้หลายอัน `ความดันโลหิตสูง`, `เบาหวาน`, `โรคหัวใจ`, `ไขมันในเลือดสูง`, `โรคไต`, `หอบหืด` + ช่องพิมพ์โรคอื่น (คั่นด้วยเครื่องหมายจุลภาค) + ตัวเลือก `ไม่มีโรคประจำตัว` (เลือกแล้วล้างตัวเลือกอื่น และกลับกัน); ต้องเลือกอย่างน้อยหนึ่งอย่าง
- ช่องติ๊ก `ยินยอมให้เก็บข้อมูลสุขภาพของฉันไว้ในระบบ` ต้องติ๊กก่อนปุ่ม `บันทึก` ใช้ได้
- ข้อความ error: `กรุณากรอกชื่อเล่น`, `กรุณากรอกชื่อ-นามสกุลจริง`, `กรุณากรอกอายุ 1–120 ปี`, `กรุณาเลือกโรคประจำตัวหรือเลือกไม่มี`

**ผลหลังบันทึกโปรไฟล์:** ชื่อผู้ใช้ในแอป (`AppData.patient`) = ชื่อเล่น; `AppData.verifiedPhone` = เบอร์ที่ล็อกอิน (รูป `0XXXXXXXXX`)

**ออกจากระบบ (หน้าตั้งค่า):** กล่องยืนยัน `ออกจากระบบ? ข้อมูลยาและประวัติในเครื่องนี้จะถูกล้างด้วย` → ถ้ายืนยัน: sign out, ล้างแคชโปรไฟล์, `AppState.resetAll()`, กลับหน้ากรอกเบอร์ (กันข้อมูลคนหนึ่งปนกับอีกคนบนเครื่องเดียวกัน)

## สถาปัตยกรรม

แพ็กเกจใหม่: `supabase_flutter`

- `lib/config.dart` — `supabaseUrl`, `supabasePublishableKey` (ค่าสาธารณะสำหรับฝั่งแอป ไม่ใช่คีย์ลับ)
- `lib/models/profile.dart` — `Profile{nickname, fullName, age, conditions, consentAt}` + `toJson`/`fromJson`
- `lib/logic/auth_validators.dart` — `String? normalizeThaiMobile(String raw)` (คืน `+66…` หรือ null), `String displayPhone(String e164)` (คืน `0…`), `String? validateProfile(...)`
- `lib/services/auth_repository.dart` — `abstract class AuthRepository`:
  - `bool get isSignedIn`, `String? get phone` (E.164)
  - `Future<void> sendOtp(String e164)`, `Future<void> verifyOtp(String e164, String code)`
  - `Future<Profile?> loadProfile()`, `Future<void> saveProfile(Profile p)`, `Future<void> signOut()`
  - ข้อผิดพลาดโยน `AuthFailure(AuthFailureKind kind)` โดย kind = `invalidCode | rateLimited | network | unknown`
- `lib/services/supabase_auth_repository.dart` — implement ด้วย `supabase_flutter` (`signInWithOtp`, `verifyOTP(type: OtpType.sms)`, ตาราง `profiles`) และแปลง exception เป็น `AuthFailure`
- `lib/state/auth_state.dart` — `ChangeNotifier` ถือสถานะ (`loading | loggedOut | needsProfile | ready`), แคชโปรไฟล์ใน `shared_preferences` คีย์ `caredose_profile` เพื่อเปิดแอปตอนไม่มีเน็ตได้ถ้ามี session และแคช
- `lib/screens/login_screen.dart`, `otp_screen.dart`, `profile_screen.dart`, `lib/auth_gate.dart`

ข้อความ error จาก `AuthFailureKind`: `invalidCode` → `รหัส OTP ไม่ถูกต้องหรือหมดอายุ`; `rateLimited` → `ขอรหัสบ่อยเกินไป กรุณารอสักครู่`; `network` → `ไม่มีอินเทอร์เน็ต กรุณาลองใหม่`; `unknown` → `เกิดข้อผิดพลาด กรุณาลองใหม่`

## ฐานข้อมูล (Supabase)

โปรเจกต์ใหม่ชื่อ `caredose` ภูมิภาค `ap-southeast-1` (สิงคโปร์) สร้างหลังผู้ใช้ยืนยันราคา

```sql
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null check (char_length(nickname) between 1 and 50),
  full_name text not null check (char_length(full_name) between 1 and 100),
  age int not null check (age between 1 and 120),
  conditions text[] not null default '{}',
  consent_at timestamptz not null,
  updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
create policy "own profile select" on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy "own profile insert" on public.profiles for insert to authenticated with check ((select auth.uid()) = id);
create policy "own profile update" on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
```

ไม่มี policy สำหรับ delete และ anon เข้าตารางไม่ได้ ตรวจด้วย advisors ของ Supabase หลังสร้าง

## ขั้นตอนที่ผู้ใช้ต้องทำเองในแดชบอร์ด Supabase

เครื่องมือของผมตั้งค่า Auth ไม่ได้: Authentication → Sign In / Providers → เปิด Phone; ในช่อง Test Phone Numbers and OTPs ใส่เบอร์ทดสอบ (เช่น `66812345678=123456`) ผู้ให้บริการ SMS จริงตั้งทีหลัง เมื่อสมัครแล้ว (นอกขอบเขตงานนี้)

## การทดสอบ

- Unit: `normalizeThaiMobile` (รับ `0812345678`, `081-234-5678`, `081 234 5678`; ปฏิเสธ `0212345678`, `081234567`, `12345`, ค่าว่าง), `displayPhone`, `validateProfile` (ทุกกรณีของ error), `Profile` JSON round-trip, การแปลง exception เป็น `AuthFailure`
- `AuthState`: ทุกการเปลี่ยนสถานะด้วย `AuthRepository` จำลอง; เปิดแอปตอนไม่มีเน็ตแต่มีแคช → `ready`; sign out ล้างแคช
- Widget: login/otp/profile แต่ละหน้า (ข้อความ error, ปุ่มนับถอยหลัง 60 วินาทีด้วย fake clock, ปุ่ม `บันทึก` ปิดจนติ๊กยินยอม, โรคประจำตัวเลือกไม่มีแล้วล้างอื่น), `AuthGate` เลือกหน้าถูก, ปุ่มออกจากระบบล้างข้อมูลหลังยืนยัน
- ตรวจมือบน emulator ด้วยเบอร์ทดสอบ: ส่งรหัส → ยืนยัน → กรอกข้อมูล → ปิด/เปิดแอปแล้วเข้าหน้าหลักเลย → ออกจากระบบ
- ตรวจ RLS ด้วยคำสั่ง SQL ว่าผู้ใช้ A อ่านแถวผู้ใช้ B ไม่ได้

## ข้อสมมุติฐานและความเสี่ยง

- ไม่ส่ง SMS จริงจนกว่าจะมีผู้ให้บริการ: ผู้ใช้จริงจะล็อกอินไม่ได้จนกว่าตั้งค่าส่วนนั้น
- Supabase ต้องการอินเทอร์เน็ตตอนล็อกอินครั้งแรกเท่านั้น หลังจากนั้นใช้แคชได้
- ข้อมูลสุขภาพ (โรคประจำตัว) เก็บบนคลาวด์ที่สิงคโปร์ ควรให้ผู้ใช้ยืนยันว่ายอมรับเรื่องการเก็บข้อมูลนอกประเทศและข้อความยินยอมตาม PDPA ก่อนใช้งานจริง
