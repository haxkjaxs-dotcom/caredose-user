# CareDose Flutter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** สร้างแอป Flutter (Dart) บน Android + iOS ที่เทียบเท่าเว็บ CareDose พร้อมแจ้งเตือนทานยาจริงที่กดปุ่ม ทานแล้ว / ยังไม่ทาน / ข้ามยา ได้จากการแจ้งเตือน

**Architecture:** Logic บริสุทธิ์ (models, dose_items, bmi, notification_plan, notification_actions, csv) แยกจาก UI; `AppState` (ChangeNotifier + `provider`) ถือ `AppData` เดียว บันทึกผ่าน `Storage` (`shared_preferences`) และสั่งตั้งแจ้งเตือนผ่าน interface `NotificationScheduler`; UI เป็น widget ธรรมดา พอร์ตจาก `src/App.tsx`

**Tech Stack:** Flutter stable (Dart 3), `provider`, `shared_preferences`, `flutter_local_notifications`, `timezone`, `flutter_timezone`, `url_launcher`, `share_plus`, `path_provider`

**Spec:** `docs/superpowers/specs/2026-11-04-caredose-flutter-design.md` (ต้นฉบับ UI/ข้อความ: `src/App.tsx`, สี/ธีม: `src/index.css`)

## Global Constraints

- โปรเจกต์ใหม่ที่ `caredose_app/` (ราก repo) ห้ามแก้ `src/`
- ข้อความ UI ภาษาไทย คัดลอกตรงตัวจาก `src/App.tsx`
- ปี พ.ศ. = ค.ศ. + 543 ในทุกที่ที่แสดงวันที่; เขียนตารางชื่อวัน/เดือนไทยเอง ไม่ใช้ `intl` (ต่างจาก spec: YAGNI, ผลลัพธ์เท่ากัน)
- JSON เก็บใน `shared_preferences` คีย์ `caredose` รูปเดียวกับ localStorage เว็บ (camelCase เหมือนเว็บ)
- รหัสสถานะ: `taken` | `skipped` (log), `pending` | `missed` (คำนวณ)
- คีย์ log: `medId|yyyy-MM-dd|HH:mm`
- แจ้งเตือน: ล่วงหน้าสูงสุด 14 วัน, รวมไม่เกิน 60 รายการ, เตือนซ้ำ +15 นาที
- ปุ่มแจ้งเตือน id: `taken`, `notyet`, `skip`; "ยังไม่ทาน" = ไม่บันทึก log และไม่เตือนซ้ำ
- โฟลเดอร์ไม่ใช่ git repo: ข้ามขั้น commit ทั้งหมด
- รันคำสั่งทั้งหมดจาก `caredose_app/` (PowerShell: `cd caredose_app`)
- รีวิวหลักการแจ้งเตือนแบบ API ตามเวอร์ชัน `flutter_local_notifications` ที่ติดตั้งจริง (ตรวจ CHANGELOG ถ้า signature ต่างจากที่ระบุ)

## Review Focus

1. เปิดแอปตอน 08:00:10 ยาเวลา 08:00 → ไม่ตั้งแจ้งเตือนย้อนหลัง ไม่ crash (Task 5)
2. JSON เก่า/เสีย/ขาดฟิลด์ (เช่นมาจากเว็บเวอร์ชันก่อน) → ใช้ค่าเริ่มต้น ไม่ crash (Task 2)
3. ยาที่ `start` ในอนาคตหรือ `end` ผ่านไปแล้ว → ไม่มีแจ้งเตือน (Task 5)
4. ยาสองตัวเวลาเดียวกัน / กดซ้ำ → id แจ้งเตือนไม่ชนกันและคงที่ต่อคีย์; กด "ยังไม่ทาน" แล้ว reschedule ต้องไม่สร้างเตือนซ้ำกลับมา (Task 5)
5. ตัวอักษร "ใหญ่มาก" (textScale สูง) → หน้าหลักไม่ overflow (Task 7)

---

### Task 1: Scaffold โปรเจกต์ + ธีม + วันที่ไทย

**Files:**
- Create: `caredose_app/` (ด้วย `flutter create`), `lib/theme.dart`, `lib/logic/thai_date.dart`
- Test: `test/thai_date_test.dart`

**Interfaces:**
- Produces:
  - `String dateKey(DateTime d)` → `yyyy-MM-dd`
  - `String todayKey(DateTime now)` (= `dateKey(now)`)
  - `String thDate(String key)` → `วันพุธที่ 4 พฤศจิกายน 2569`
  - `String thDateShort(String key)` → `4 พ.ย. 2569`
  - `String thTime(DateTime d)` → `08:05` (24 ชม. สองหลัก)
  - `String thMonthYear(int year, int month)` → `พฤศจิกายน 2569`
  - `ThemeData buildTheme()`; `double textScaleFor(String size)` (`normal`→1.0, `large`→1.25, `xl`→1.5)
  - ค่าสี brand/brandDark/paper/ink ใน `theme.dart` อ่านจาก `src/index.css`

- [ ] **Step 1:** `flutter create --org com.caredose --project-name caredose --platforms=android,ios caredose_app` (รันที่รากโปรเจกต์); `cd caredose_app; flutter pub add provider shared_preferences flutter_local_notifications timezone flutter_timezone url_launcher share_plus path_provider`
- [ ] **Step 2: เขียน test ที่ fail** `test/thai_date_test.dart`: `thDate('2026-11-04') == 'วันพุธที่ 4 พฤศจิกายน 2569'`; `thDateShort('2026-01-09') == '9 ม.ค. 2569'`; `thTime(DateTime(2026,1,1,8,5)) == '08:05'`; `dateKey(DateTime(2026,3,7)) == '2026-03-07'`; `textScaleFor('xl') == 1.5`
- [ ] **Step 3:** รัน `flutter test test/thai_date_test.dart` → FAIL (ไม่มีฟังก์ชัน)
- [ ] **Step 4:** เขียน `thai_date.dart` และ `theme.dart` ตาม Interfaces; `main.dart` แสดง `MaterialApp` ว่าง ๆ ด้วย `buildTheme()` (ยังไม่ต่อ UI)
- [ ] **Step 5:** รัน `flutter test test/thai_date_test.dart` → PASS; `flutter analyze` → No issues

### Task 2: Models + Storage

**Files:**
- Create: `lib/models/models.dart`, `lib/services/storage.dart`
- Test: `test/models_test.dart`, `test/storage_test.dart`

**Interfaces:**
- Consumes: `dateKey` (Task 1)
- Produces (ฟิลด์ตรงกับ `Data` ใน `src/App.tsx:3-24`; ทุกคลาสมี `toJson()` และ `factory X.fromJson(Map<String, dynamic>)` ที่ทนฟิลด์ขาด/ผิดชนิดโดยใช้ค่าเริ่มต้น):
  - `Med{id,name,dosage,meal,List<String> times,start,end,note,color}`; `copyWith`
  - `DoseLog{String status,String at}`; `Doctor{id,name,spec,phone}`; `Relative{id,name,rel,phone}`; `Appt{id,at,place,dept,note,String? status,previousAt,statusNote}`; `BmiRecord{id,double w,double h,double v,cat,at}`
  - `AppData{patient,List<Med> meds,Map<String,DoseLog> logs,doctors,relatives,appts,bmis,size,bool notify,notifyChannel,bool repeatReminder,verifiedPhone}`; `AppData.seed(DateTime now)` (ค่าเท่ากับ `seed()` ใน `src/App.tsx:33-50`; นัดหมายตัวอย่างอยู่ +5 วันเวลา 09:30 รูป `yyyy-MM-ddT09:30`); `copyWith`
  - `class Storage { Storage(SharedPreferences p); AppData load(DateTime now); Future<void> save(AppData d); Set<String> loadDismissed(); Future<void> saveDismissed(Set<String> s); }` คีย์ `caredose` และ `caredose_dismissed`

- [ ] **Step 1: เขียน test ที่ fail**
  - `AppData.seed(now)` → `fromJson(toJson())` เท่ากับเดิม (เทียบ `toJson()` สองก้อน)
  - **Review Focus 2:** `Storage.load` ได้ seed เมื่อ prefs ว่าง, เมื่อค่าเป็น `'not json'`, และเมื่อ JSON เป็น `{"patient":"ก"}` (ได้ patient `ก` + ฟิลด์อื่นจาก seed, meds เป็น seed); เมื่อ med ไม่มี `times` → `times == []` ไม่ throw
  - `save` แล้ว `load` ได้ข้อมูลเดิม; `saveDismissed({'a'})` แล้ว `loadDismissed() == {'a'}`
- [ ] **Step 2:** รัน `flutter test test/models_test.dart test/storage_test.dart` → FAIL
- [ ] **Step 3:** implement ตาม Interfaces (`SharedPreferences.setMockInitialValues` ในเทสต์)
- [ ] **Step 4:** รันเทสต์ → PASS

### Task 3: Logic — dose items และ BMI

**Files:**
- Create: `lib/logic/dose_items.dart`, `lib/logic/bmi.dart`
- Test: `test/dose_items_test.dart`, `test/bmi_test.dart`

**Interfaces:**
- Consumes: `AppData`, `Med`, `DoseLog` (Task 2)
- Produces:
  - `enum DoseStatus { taken, skipped, pending, missed }` และ `String doseStatusLabel(DoseStatus s)` (`ทานแล้ว`/`ข้าม`/`รอทาน`/`เลยเวลา`)
  - `class DoseItem { final Med med; final String time; final String key; final DoseLog? log; final DoseStatus status; }`
  - `List<DoseItem> itemsFor(AppData d, String date, DateTime now)` — พอร์ต `src/App.tsx:68-81`: ข้ามยาถ้า `date < start` หรือ `end` ไม่ว่างและ `date > end`; `key = '${med.id}|$date|$time'`; มี log → status ตาม log, ไม่มี log และ `DateTime.parse('${date}T$time') < now` → missed, อื่น ๆ → pending; เรียงตาม `time` แล้ว `med.name`
  - `DateTime doseTime(String date, String time)`
  - `String? validateBmiInput(double? w, double? h)` → `null` ถ้าถูก, ไม่เช่นนั้นข้อความ `กรุณากรอกน้ำหนัก (กก.) และส่วนสูง (ซม.) ให้ถูกต้อง` (น้ำหนัก 0<w<400, ส่วนสูง 50<h<250)
  - `double bmiValue(double w, double h)` (ปัด 1 ตำแหน่ง); `String bmiCategory(double v)` (`ต่ำกว่าเกณฑ์`/`ปกติ`/`สูงกว่าเกณฑ์` ที่ <18.5 / <25 / ที่เหลือ)

- [ ] **Step 1: เขียน test ที่ fail**
  - `itemsFor`: ยา 2 ตัวเวลา 08:00 ชื่อ `ข`,`ก` → เรียง `ก` ก่อน; ยา `start` พรุ่งนี้ → ว่าง; ยา `end` เมื่อวาน → ว่าง; now=09:00 ไม่มี log → `missed`; now=07:00 → `pending`; มี log taken → `taken` แม้เวลาเลยแล้ว
  - `bmiValue(58,155) == 24.1`; `bmiCategory(18.4)=='ต่ำกว่าเกณฑ์'`, `(18.5)=='ปกติ'`, `(24.9)=='ปกติ'`, `(25)=='สูงกว่าเกณฑ์'`; `validateBmiInput(0,155) != null`, `(58,49) != null`, `(58,155) == null`, `(null,155) != null`
- [ ] **Step 2:** รัน → FAIL
- [ ] **Step 3:** implement
- [ ] **Step 4:** รัน → PASS

### Task 4: AppState

**Files:**
- Create: `lib/state/app_state.dart`
- Test: `test/app_state_test.dart`

**Interfaces:**
- Consumes: `Storage`, `AppData` (Task 2), `itemsFor`/`DoseItem`/`DoseStatus`/`doseTime` (Task 3)
- Produces:
  - `abstract class NotificationScheduler { Future<void> reschedule(AppData d, Set<String> dismissed, DateTime now); }`
  - `class AppState extends ChangeNotifier { AppState(Storage storage, NotificationScheduler scheduler, {DateTime Function()? clock}); AppData data; Set<String> dismissed; DateTime now;`
    `void tick();` (อัปเดต `now` จาก clock + notify)
    `Future<void> reload();` (โหลดจาก storage ใหม่ — ใช้หลัง background action)
    `void mark(DoseItem it, DoseStatus s);` (`taken`/`skipped`) `void undo(DoseItem it);`
    `List<String> markMeal(List<DoseItem> items);` (บันทึก `taken` เฉพาะรายการไม่มี log และ `doseTime <= now`; คืนคีย์ที่บันทึก) `void undoKeys(List<String> keys);`
    `void saveMed(Med m);` (แทนที่ถ้า id ซ้ำ ไม่เช่นนั้นต่อท้าย) `void saveRelative(Relative r); void deleteRelative(String id);`
    `void addBmi(double w, double h);` (เพิ่มหน้าสุด, `v`/`cat` จาก Task 3, `at` = ISO ของ now)
    `void setPatient(String); setSize(String); setNotify(bool); setChannel(String); setRepeat(bool); setVerifiedPhone(String); Future<void> resetAll();` }`
  - ทุก mutation: บันทึก storage + เรียก `scheduler.reschedule(data, dismissed, now)` + `notifyListeners()`

- [ ] **Step 1: เขียน test ที่ fail** (ใช้ `FakeScheduler` นับจำนวนครั้ง และ clock คงที่)
  - `mark` taken → `data.logs[key]?.status == 'taken'`, scheduler ถูกเรียก 1 ครั้ง, storage มีค่าใหม่
  - `markMeal` ที่ now=09:00 กับรายการ 08:00 (ไม่มี log), 18:00, และอีกตัว 08:00 ที่มี log → คืน 1 คีย์; `undoKeys` ลบ log นั้น
  - `saveMed` id ใหม่ → length+1; id เดิม → แทนที่; `deleteRelative` ลบ; `addBmi(58,155)` → `bmis.first.v == 24.1`
  - `resetAll` → `data` เท่า `AppData.seed(now)` และ `dismissed` ว่าง
- [ ] **Step 2:** รัน `flutter test test/app_state_test.dart` → FAIL
- [ ] **Step 3:** implement
- [ ] **Step 4:** รัน → PASS

### Task 5: ตารางแจ้งเตือน + การกดปุ่ม (logic บริสุทธิ์)

**Files:**
- Create: `lib/services/notification_plan.dart`, `lib/services/notification_actions.dart`
- Test: `test/notification_plan_test.dart`, `test/notification_actions_test.dart`

**Interfaces:**
- Consumes: `AppData`, `itemsFor`-style กฎช่วง start/end, `doseTime`, `dateKey` (Task 1–3)
- Produces:
  - `class PlannedNotification { final int id; final DateTime at; final String title; final String body; final String payload; final bool isRepeat; }` (`payload` = คีย์ log)
  - `int notificationId(String key, {required bool repeat})` — hash FNV-1a ของ key `& 0x3fffffff`, คูณ 2 แล้วบวก 1 ถ้า repeat (คงที่ต่อ key, หลัก/ซ้ำไม่ชนกัน)
  - `List<PlannedNotification> planNotifications(AppData d, Set<String> dismissed, DateTime now, {int maxDays = 14, int maxCount = 60})` —
    - ว่างถ้า `!d.notify`
    - วนวันที่ `today .. today+maxDays-1` × ยา × เวลา ตามกฎ start/end; ข้ามถ้ามี log
    - แจ้งหลัก: `at = doseTime`, รวมเฉพาะ `at > now`; title `ถึงเวลาทานยา`, body `'${med.name} ${med.dosage}'` (ต่อ ` • ${med.meal}` ถ้ามี)
    - เตือนซ้ำ (`isRepeat`): เมื่อ `d.repeatReminder` และ key ไม่อยู่ใน `dismissed`, `at = doseTime + 15 นาที`, รวมเฉพาะ `at > now`; title `เตือนอีกครั้ง: ยังไม่ได้ทานยา`
    - เรียงตาม `at` แล้วตัดเหลือ `maxCount`
  - `({AppData data, Set<String> dismissed}) applyDoseAction(AppData d, Set<String> dismissed, String actionId, String key, DateTime now)` — `taken`/`skip` → เขียน log (`taken`/`skipped`, `at = now.toIso8601String()`); `notyet` → เพิ่ม key ใน `dismissed` ไม่แตะ log; id อื่น → คืนเดิม; ตัด `dismissed` ที่วันที่ใน key เก่ากว่า 2 วันออก

- [ ] **Step 1: เขียน test ที่ fail**
  - plan: now=08:00:10, ยา 08:00 → ไม่มีรายการ 08:00 วันนี้ แต่มี 08:00 พรุ่งนี้ (**Review Focus 1**)
  - plan: ยา `start` = พรุ่งนี้ → ไม่มีรายการวันนี้; `end` = เมื่อวาน → ว่าง (**Review Focus 3**)
  - plan: `notify=false` → ว่าง; มี log ของ key → ไม่มีทั้งหลักและซ้ำของ key นั้น; `repeatReminder=false` → ไม่มี `isRepeat`; key อยู่ใน `dismissed` → ไม่มีซ้ำของ key นั้น แต่ยังมีหลักของวันถัดไป (**Review Focus 4**)
  - plan: ยา 4 เวลา/วัน 14 วัน → `length == 60` และ `at` เรียงจากน้อยไปมาก; ยาสองตัวเวลาเดียวกัน → สอง id ต่างกัน; `notificationId(k, repeat:false) == notificationId(k, repeat:false)` และ `!= notificationId(k, repeat:true)`
  - actions: `taken` → log taken; `skip` → log skipped; `notyet` → log ไม่เปลี่ยน, `dismissed` มี key; `planNotifications` หลัง `notyet` ไม่มีซ้ำของ key นั้น; actionId แปลก → ไม่เปลี่ยน
- [ ] **Step 2:** รัน → FAIL
- [ ] **Step 3:** implement
- [ ] **Step 4:** รัน → PASS

### Task 6: NotificationService + ตั้งค่าแพลตฟอร์ม + ต่อ main

**Files:**
- Create: `lib/services/notification_service.dart`
- Modify: `lib/main.dart`, `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle(.kts)`, `ios/Runner/AppDelegate.swift`
- Test: `test/notification_service_test.dart` (เฉพาะส่วนที่ไม่แตะ plugin)

**Interfaces:**
- Consumes: `planNotifications`, `notificationId`, `applyDoseAction` (Task 5), `NotificationScheduler`, `Storage` (Task 2/4)
- Produces:
  - `class NotificationService implements NotificationScheduler { Future<void> init({void Function()? onAction}); Future<bool> requestPermissions(); Future<bool> permissionsGranted(); Future<void> reschedule(AppData d, Set<String> dismissed, DateTime now); }`
  - `@pragma('vm:entry-point') void notificationBackgroundHandler(NotificationResponse r)` — เปิด `SharedPreferences`, `Storage.load`, `applyDoseAction`, `save`/`saveDismissed`, แล้ว `cancel` แจ้งเตือนซ้ำ (`notificationId(key, repeat:true)`) ของ key นั้น
  - ค่าคงที่: channel `dose_reminders` (importance max, heads-up), iOS category `dose`

- [ ] **Step 1: เขียน test ที่ fail:** ฟังก์ชันช่วยแปลง `PlannedNotification` → ข้อมูลที่ส่งเข้า plugin (`payload`, `id`) ไม่เปลี่ยนค่า และรายการ action คือ 3 ปุ่มลำดับ `taken`,`notyet`,`skip` ป้ายกำกับ `ทานแล้ว`,`ยังไม่ทาน`,`ข้ามยา` (ดึงเป็นฟังก์ชัน `List<(String id,String label)> doseActions()` ที่เทสต์ได้)
- [ ] **Step 2:** รัน → FAIL
- [ ] **Step 3:** implement `NotificationService`:
  - `init`: `tz.initializeTimeZones()`, ตั้ง local location จาก `flutter_timezone`, `initialize` พร้อม `onDidReceiveNotificationResponse` (foreground: ทำ `applyDoseAction` ผ่านโค้ดเดียวกับ background แล้วเรียก `onAction`) และ `onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler`
  - Android: `AndroidNotificationAction` สามปุ่ม (`cancelNotification: true`, `showsUserInterface: false`), channel ความสำคัญสูง
  - iOS: `DarwinNotificationCategory('dose', actions: [...])` ในการ initialize และ `categoryIdentifier: 'dose'` ตอนแสดง
  - `reschedule`: `cancelAll()` แล้ววน `planNotifications(...)` เรียก `zonedSchedule` (โหมด exact ถ้าอนุญาต ไม่เช่นนั้น inexact) ด้วย `payload` และ id จากแผน
  - `requestPermissions`: Android 13+ `POST_NOTIFICATIONS` + exact alarm; iOS alert/sound/badge
- [ ] **Step 4:** ตั้งค่า Android: permissions `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`; receiver ของ plugin (`ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver`, `ActionBroadcastReceiver`); เปิด core library desugaring ตามคู่มือ plugin เวอร์ชันที่ติดตั้ง; iOS: `UNUserNotificationCenter.current().delegate` ใน `AppDelegate`
- [ ] **Step 5:** `main.dart`: สร้าง `Storage`, `NotificationService`, `AppState`, เรียก `init`, `reschedule` ตอนเปิด, ห่อด้วย `ChangeNotifierProvider`; ต่อ `WidgetsBindingObserver` ให้ `reload()` + `tick()` เมื่อแอปกลับมา foreground (**ครอบคลุมโซนเวลา/ข้ามเที่ยงคืน**)
- [ ] **Step 6:** รัน `flutter test` ทั้งหมด → PASS; `flutter analyze` → No issues; `flutter build apk --debug` → สำเร็จ

### Task 7: App shell + widget ร่วม + หน้าหลัก + ฟอร์มยา

**Files:**
- Create: `lib/app.dart`, `lib/widgets/common.dart` (Card, Badge, SectionTitle, LabeledField, `showAppSheet`), `lib/screens/home_screen.dart`, `lib/widgets/med_form.dart`
- Modify: `lib/main.dart` (ใช้ `CareDoseApp`)
- Test: `test/home_screen_test.dart`, `test/app_shell_test.dart`

**Interfaces:**
- Consumes: `AppState` (Task 4), `itemsFor`/`DoseItem` (Task 3), `thDate`/`thTime` (Task 1)
- Produces:
  - `class CareDoseApp extends StatelessWidget` — `MaterialApp` + `textScaler` ตาม `data.size`; `Scaffold` มีหัว (`CareDose` / `ยาอุ่นใจ` + ปุ่ม `ตั้งค่า`), แท็บล่าง 4 อัน `หน้าหลัก`,`BMI`,`ประวัติ`,`ญาติ/นัด` (ดู `src/App.tsx:117-169`); `Timer.periodic(30s)` เรียก `tick()`; หน้า bmi/history/contacts และ sheet ตั้งค่าเป็น placeholder จนกว่า Task 8–11 แทนที่
  - `class HomeScreen`, `class MedForm` — พอร์ต `src/App.tsx:297-450` และ `452-494` (การ์ดเวลาถัดไป, กลุ่มตามมื้อ, ทานแล้ว/ข้ามยา/ยกเลิกการบันทึก, ทานทั้งมื้อ + ย้อนกลับ 6 วินาที, รายละเอียดยา, แพทย์ + ปุ่มโทร `url_launcher` `tel:`, ฟอร์มพร้อมข้อความ error ตามเว็บ)
  - `Future<void> callNumber(BuildContext c, String phone)` ใน `common.dart` — ถ้า `launchUrl` ไม่ได้แสดง SnackBar `โทรไม่ได้`

- [ ] **Step 1: เขียน test ที่ fail** (ใช้ `AppState` + fake scheduler + `SharedPreferences` mock)
  - shell: pump `CareDoseApp`, แตะ `ประวัติ`, `ญาติ/นัด`, `BMI`, `หน้าหลัก` ไม่ throw และเห็นข้อความหัว `CareDose`
  - home: เห็นยาจาก seed ทั้งสามตัว; แตะ `ทานแล้ว` ที่ยาตัวแรก → log ถูกบันทึกใน `AppState` และปุ่มกลายเป็น `ยกเลิกการบันทึก`
  - home: ฟอร์มยา submit ชื่อว่าง → `กรุณากรอกชื่อยา`; end ก่อน start → `วันที่สิ้นสุดต้องไม่ก่อนวันที่เริ่ม`
  - **Review Focus 5:** ตั้ง `size='xl'` (textScale 1.5) บนหน้าจอ 360×640 → `tester.takeException()` เป็น null
- [ ] **Step 2:** รัน → FAIL
- [ ] **Step 3:** implement ตาม Interfaces (คัดข้อความตรงตัวจาก `App.tsx`)
- [ ] **Step 4:** รัน `flutter test` → PASS

### Task 8: หน้า BMI

**Files:**
- Create: `lib/screens/bmi_screen.dart`
- Modify: `lib/app.dart` (แทน placeholder)
- Test: `test/bmi_screen_test.dart`

**Interfaces:**
- Consumes: `validateBmiInput`, `bmiCategory` (Task 3), `AppState.addBmi` (Task 4)
- Produces: `class BmiScreen` พอร์ต `src/App.tsx:515-562` (ฟอร์ม น้ำหนัก/ส่วนสูง, การ์ดค่าล่าสุดสีเขียวเมื่อ `ปกติ` อื่น ๆ เหลือง, ข้อความ "ไม่ใช่การวินิจฉัยทางการแพทย์", ประวัติ)

- [ ] **Step 1: test ที่ fail:** กรอก `58`,`155` กด `คำนวณ BMI` → เห็น `24.1` และ `ปกติ`; กรอกน้ำหนักว่างกด → เห็นข้อความ error จาก `validateBmiInput`; กรอก `abc` → error ไม่ throw
- [ ] **Step 2:** รัน → FAIL; **Step 3:** implement; **Step 4:** รัน → PASS

### Task 9: หน้าประวัติ + ส่งออก CSV

**Files:**
- Create: `lib/screens/history_screen.dart`, `lib/widgets/calendar_picker.dart`, `lib/widgets/date_range_picker.dart`, `lib/services/csv_export.dart`
- Modify: `lib/app.dart`
- Test: `test/csv_export_test.dart`, `test/history_screen_test.dart`

**Interfaces:**
- Consumes: `itemsFor`, `doseStatusLabel` (Task 3), `thDate`, `thMonthYear`, `dateKey` (Task 1)
- Produces:
  - `String buildCsv(AppData d, String from, String to, DateTime now)` — `﻿` นำหน้า, คอลัมน์ `วันที่,เวลาที่กำหนด,ชื่อยา,ปริมาณ,สถานะ,เวลาที่บันทึก,หมายเหตุ`, ทุกเซลล์ครอบด้วย `"` และ `"` ในเซลล์เป็น `""`, ขึ้นบรรทัดด้วย `\r\n`, วนทุกวันตั้งแต่ `from` ถึง `to` รวมปลาย
  - `Future<void> shareCsv(String csv, String from, String to)` — เขียนไฟล์ `caredose_${from}_$to.csv` ใน temp dir แล้ว `Share.shareXFiles`; ล้มเหลวให้ throw ให้ UI แสดง SnackBar
  - `class CalendarPicker({required String date, required ValueChanged<String> onChanged, String label, CalendarMeta Function(String)? dayMeta})` และ `class DateRangePicker` — พอร์ต `src/App.tsx:564-642`
  - `class HistoryScreen` — พอร์ต `src/App.tsx:644-722` (สรุปรายวัน ครบ/รอทาน/พลาด/ข้าม/ไม่มี, ตัวนับ 4 สถานะ, รายการ, Export)

- [ ] **Step 1: test ที่ fail**
  - csv: ขึ้นต้นด้วย BOM; ชื่อยา `ยา "A"` ออกเป็น `"ยา ""A"""`; ช่วง 2 วันได้ทุกรายการทั้งสองวัน และไม่มีรายการนอกช่วง; ยาที่ `end` ก่อน `from` ไม่ปรากฏ; ไม่มียาในช่วง → มีแค่แถวหัว
  - screen: เลือกวันที่ในปฏิทินแล้วรายการเปลี่ยน; ปุ่ม Export ปิดเมื่อ `from > to`
- [ ] **Step 2:** รัน → FAIL; **Step 3:** implement; **Step 4:** รัน → PASS

### Task 10: หน้าญาติ/นัด

**Files:**
- Create: `lib/screens/contacts_screen.dart`, `lib/widgets/person_form.dart`
- Modify: `lib/app.dart`
- Test: `test/contacts_screen_test.dart`

**Interfaces:**
- Consumes: `AppState.saveRelative/deleteRelative` (Task 4), `callNumber` (Task 7), `thDate`, `thTime`
- Produces: `class ContactsScreen`, `class PersonForm({required String title, required List<(String key,String label)> fields, required Map<String,String> initial, required ValueChanged<Map<String,String>> onSave, VoidCallback? onDelete})` — พอร์ต `src/App.tsx:496-511` และ `724-814` (สรุปผู้ป่วย "ทานแล้ว X จาก Y รายการ", ญาติ + โทร/แก้ไข/ลบพร้อมยืนยัน, นัดหมายตามสถานะ pending/confirmed/rescheduled/cancelled)

- [ ] **Step 1: test ที่ fail:** เห็นญาติ `สมชาย` จาก seed; เพิ่มญาติโดยไม่กรอกเบอร์ → `กรุณากรอกชื่อและเบอร์โทร`; เพิ่มสำเร็จแล้วอยู่ในรายการ; ลบต้องผ่านกล่องยืนยัน `ต้องการลบ "…" ใช่หรือไม่?`; นัด `rescheduled` แสดง `กำหนดเดิม`
- [ ] **Step 2:** รัน → FAIL; **Step 3:** implement; **Step 4:** รัน → PASS

### Task 11: หน้าตั้งค่า

**Files:**
- Create: `lib/screens/settings_sheet.dart`
- Modify: `lib/app.dart` (ปุ่ม `ตั้งค่า` เปิด sheet)
- Test: `test/settings_sheet_test.dart`

**Interfaces:**
- Consumes: `AppState` setters/`resetAll` (Task 4), `NotificationService.permissionsGranted/requestPermissions` (Task 6) ผ่าน provider หรือพารามิเตอร์ (ตัวเลือกให้เทสต์ใช้ fake)
- Produces: `class SettingsSheet` พอร์ต `src/App.tsx:171-295` (ชื่อผู้ใช้, ขนาดตัวอักษร ปกติ/ใหญ่/ใหญ่มาก, สวิตช์แจ้งเตือน, ช่องทางแจ้งเตือน, เบอร์ที่ยืนยัน + ขั้นตอน OTP จำลอง (OTP 6 หลักใดก็ได้ผ่าน), ตัวอย่าง SMS, เตือนซ้ำ, ล้างข้อมูล, เกี่ยวกับแอป) บวกแบนเนอร์เตือนเมื่อ `permissionsGranted()` เป็น false พร้อมปุ่มขอสิทธิ์; ป้ายระบุว่า SMS/OTP เป็นตัวอย่างและแจ้งเตือนจริงส่งเฉพาะผ่านแอป

- [ ] **Step 1: test ที่ fail:** เปลี่ยนขนาดเป็น `ใหญ่มาก` → `AppState.data.size == 'xl'`; ปิดสวิตช์แจ้งเตือน → `data.notify == false` และ scheduler ถูกเรียก; OTP `12` → error `กรุณากรอกรหัส OTP 6 หลัก`; OTP `123456` → `verifiedPhone` เปลี่ยน; เบอร์สั้นเกิน → `กรุณากรอกเบอร์โทรศัพท์ให้ถูกต้อง`; permission=false → เห็นแบนเนอร์
- [ ] **Step 2:** รัน → FAIL; **Step 3:** implement; **Step 4:** รัน → PASS

### Task 12: ตรวจรวมและทดสอบบนอุปกรณ์

- [ ] **Step 1:** `flutter analyze` → No issues found
- [ ] **Step 2:** `flutter test` → All tests passed
- [ ] **Step 3:** `flutter build apk --debug` → Built `app-debug.apk`
- [ ] **Step 4 (มือ, บน emulator/เครื่องจริง Android):** ตั้งยาที่ +2 นาที → แจ้งเตือนเด้งพร้อมปุ่ม; กด `ทานแล้ว` ขณะปิดแอป → เปิดแอปแล้วรายการเป็น `ทานแล้ว`; กด `ยังไม่ทาน` → ไม่มีเตือนซ้ำใน 15 นาที แต่รอบยาถัดไปเตือน; กด `ข้ามยา` → รายการเป็น `ข้าม`
- [ ] **Step 5:** แจ้งผู้ใช้ว่า iOS ยังไม่ได้ตรวจ (ต้องใช้ Mac) และสรุปผลทุกข้อ
