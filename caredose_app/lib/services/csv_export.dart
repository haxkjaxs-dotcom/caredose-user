import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../logic/dose_items.dart';
import '../logic/thai_date.dart';
import '../models/models.dart';

/// CSV (UTF-8 with BOM so Excel reads Thai) of every dose from [from] to [to] inclusive.
String buildCsv(AppData d, String from, String to, DateTime now) {
  final rows = <List<String>>[
    ['วันที่', 'เวลาที่กำหนด', 'ชื่อยา', 'ปริมาณ', 'สถานะ', 'เวลาที่บันทึก', 'หมายเหตุ'],
  ];
  for (var t = DateTime.parse(from); dateKey(t).compareTo(to) <= 0; t = DateTime(t.year, t.month, t.day + 1)) {
    final date = dateKey(t);
    for (final i in itemsFor(d, date, now)) {
      final at = i.log == null ? '' : DateTime.parse(i.log!.at);
      rows.add([
        date,
        i.time,
        i.med.name,
        i.med.dosage,
        doseStatusLabel(i.status),
        at is DateTime ? '${thDateShort(dateKey(at))} ${thTime(at)}' : '',
        i.med.note,
      ]);
    }
  }
  String esc(String s) => '"${s.replaceAll('"', '""')}"';
  return '﻿${rows.map((r) => r.map(esc).join(',')).join('\r\n')}';
}

/// Writes the CSV to a temp file and opens the system share sheet.
Future<void> shareCsv(String csv, String from, String to) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/caredose_${from}_$to.csv');
  await file.writeAsString(csv, encoding: utf8);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/csv')], subject: 'CareDose $from ถึง $to'));
}
