/// User profile stored in Supabase `profiles` and cached locally (same JSON).
class Profile {
  final String nickname, fullName;
  final int age;
  final List<String> conditions;
  final DateTime consentAt;

  const Profile({
    required this.nickname,
    required this.fullName,
    required this.age,
    required this.conditions,
    required this.consentAt,
  });

  factory Profile.fromJson(Map<String, dynamic> j) {
    final nickname = j['nickname'];
    final fullName = j['full_name'];
    final age = j['age'];
    final conditions = j['conditions'];
    final consent = j['consent_at'];
    if (nickname is! String || fullName is! String || age is! int || conditions is! List || consent is! String) {
      throw const FormatException('invalid profile');
    }
    return Profile(
      nickname: nickname,
      fullName: fullName,
      age: age,
      conditions: conditions.whereType<String>().toList(),
      consentAt: DateTime.parse(consent),
    );
  }

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'full_name': fullName,
        'age': age,
        'conditions': conditions,
        'consent_at': consentAt.toUtc().toIso8601String(),
      };
}
