import '../models/remote_plan.dart';

/// Medication plans and dose logs on the server. Methods throw only `AuthFailure`.
abstract class MedRepository {
  Future<List<RemotePlan>> fetchPlans();
  Future<List<RemoteLog>> fetchLogs(DateTime since);
  Future<void> upsertLog(LogOp op);

  /// The patient's own appointments, read-only (the Admin web owns them).
  Future<List<RemoteAppt>> fetchAppointments();

  /// The doctor's name typed on the patient in the Admin web; '' when none.
  Future<String> fetchDoctorName();
}
