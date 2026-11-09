import '../models/remote_plan.dart';

/// Medication plans and dose logs on the server. Methods throw only `AuthFailure`.
abstract class MedRepository {
  Future<List<RemotePlan>> fetchPlans();
  Future<List<RemoteLog>> fetchLogs(DateTime since);
  Future<void> upsertLog(LogOp op);
}
