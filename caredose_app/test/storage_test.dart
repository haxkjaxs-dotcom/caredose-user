import 'package:caredose/models/models.dart';
import 'package:caredose/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Storage> make(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  return Storage(await SharedPreferences.getInstance());
}

void main() {
  final now = DateTime(2026, 11, 4, 10, 0);

  test('empty prefs returns seed', () async {
    final s = await make({});
    expect(s.load(now).toJson(), AppData.seed(now).toJson());
  });

  test('corrupt JSON returns seed', () async {
    final s = await make({'caredose': 'not json'});
    expect(s.load(now).toJson(), AppData.seed(now).toJson());
  });

  test('non-object JSON returns seed', () async {
    final s = await make({'caredose': '[1,2]'});
    expect(s.load(now).toJson(), AppData.seed(now).toJson());
  });

  test('partial JSON merges over seed', () async {
    final s = await make({'caredose': '{"patient":"ก"}'});
    final d = s.load(now);
    expect(d.patient, 'ก');
    expect(d.meds.length, 3);
  });

  test('save then load returns same data', () async {
    final s = await make({});
    final d = AppData.seed(now).copyWith(patient: 'สมชาย');
    await s.save(d);
    expect(s.load(now).patient, 'สมชาย');
  });

  test('dismissed set persists', () async {
    final s = await make({});
    expect(s.loadDismissed(), <String>{});
    await s.saveDismissed({'a|2026-11-04|08:00'});
    expect(s.loadDismissed(), {'a|2026-11-04|08:00'});
  });
}
