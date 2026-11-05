import 'package:caredose/models/models.dart';
import 'package:caredose/services/csv_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 10, 12);
  AppData data(List<Med> meds, {Map<String, DoseLog> logs = const {}}) => AppData(meds: meds, logs: logs);
  const med = Med(id: '1', name: 'ยา "A"', dosage: '1 เม็ด', times: ['08:00'], start: '2026-11-01', note: 'หมายเหตุ');

  test('starts with BOM and Thai header row', () {
    final csv = buildCsv(data([med]), '2026-11-04', '2026-11-04', now);
    expect(csv.startsWith('﻿'), true);
    expect(csv.substring(1).split('\r\n').first,
        '"วันที่","เวลาที่กำหนด","ชื่อยา","ปริมาณ","สถานะ","เวลาที่บันทึก","หมายเหตุ"');
  });

  test('quotes inside cells are doubled', () {
    final csv = buildCsv(data([med]), '2026-11-04', '2026-11-04', now);
    expect(csv.contains('"ยา ""A"""'), true);
  });

  test('cells that Excel would run as formulas are neutralised', () {
    for (final evil in ['=HYPERLINK("http://x","คลิก")', '+1+1', '-2+3', '@SUM(A1)', '\t=1', '\r=1']) {
      final m = med.copyWith(note: evil);
      final csv = buildCsv(data([m]), '2026-11-04', '2026-11-04', now);
      final line = csv.split('\r\n')[1];
      expect(line.endsWith('"\'${evil.replaceAll('"', '""')}"'), true, reason: evil); // note is the last cell
    }
    // plain text and negative-looking dosages that are not at the start stay untouched
    expect(buildCsv(data([med]), '2026-11-04', '2026-11-04', now).contains('"หมายเหตุ"'), true);
  });

  test('range is inclusive on both ends and excludes outside days', () {
    final csv = buildCsv(data([med]), '2026-11-04', '2026-11-05', now);
    final lines = csv.split('\r\n');
    expect(lines.length, 3);
    expect(lines[1].startsWith('"2026-11-04"'), true);
    expect(lines[2].startsWith('"2026-11-05"'), true);
    expect(csv.contains('2026-11-03'), false);
    expect(csv.contains('2026-11-06'), false);
  });

  test('statuses are Thai and logged time is filled', () {
    final d = data([med], logs: {'1|2026-11-04|08:00': const DoseLog('taken', '2026-11-04T08:05:00')});
    final lines = buildCsv(d, '2026-11-04', '2026-11-05', now).split('\r\n');
    expect(lines[1].contains('"ทานแล้ว"'), true);
    expect(lines[1].contains('08:05'), true);
    expect(lines[2].contains('"เลยเวลา"'), true);
  });

  test('med that ended before range and reversed range yield header only', () {
    final ended = med.copyWith(end: '2026-11-02');
    expect(buildCsv(data([ended]), '2026-11-04', '2026-11-05', now).split('\r\n').length, 1);
    expect(buildCsv(data([med]), '2026-11-05', '2026-11-04', now).split('\r\n').length, 1);
  });
}
