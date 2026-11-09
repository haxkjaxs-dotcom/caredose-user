import 'dart:async';

import 'package:caredose/models/remote_plan.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/services/med_repository.dart';

class FakeMedRepository implements MedRepository {
  List<RemotePlan> plans = [];
  List<RemoteLog> logs = [];
  AuthFailure? failure;

  /// Any non-AuthFailure error to throw from fetchPlans.
  Object? crash;
  final order = <String>[];

  /// When set, fetchPlans waits for it (to hold a pull open).
  Completer<void>? gate;
  int plansCalls = 0, logsCalls = 0;
  DateTime? lastSince;
  /// Successful upserts, in order.
  final upserts = <LogOp>[];
  int upsertCalls = 0;

  /// Runs before each upsert; throw from it (or await a gate) to script failures.
  Future<void> Function(LogOp op)? onUpsert;

  @override
  Future<List<RemotePlan>> fetchPlans() async {
    plansCalls++;
    order.add('fetchPlans');
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    if (crash != null) throw crash!;
    return plans;
  }

  @override
  Future<List<RemoteLog>> fetchLogs(DateTime since) async {
    logsCalls++;
    lastSince = since;
    if (failure != null) throw failure!;
    return logs;
  }

  @override
  Future<void> upsertLog(LogOp op) async {
    upsertCalls++;
    await onUpsert?.call(op);
    upserts.add(op);
  }
}
