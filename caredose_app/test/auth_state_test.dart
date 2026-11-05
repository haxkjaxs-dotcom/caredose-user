import 'package:caredose/models/profile.dart';
import 'package:caredose/services/auth_repository.dart';
import 'package:caredose/state/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth_repository.dart';

const cacheKey = 'caredose_profile';

Future<(AuthState, FakeAuthRepository, SharedPreferences, List<String>)> make({
  FakeAuthRepository? repo,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final r = repo ?? FakeAuthRepository();
  final events = <String>[];
  final s = AuthState(
    r,
    p,
    onSignedIn: (profile, phone) => events.add('in:${profile.nickname}:$phone'),
    onSignedOut: () => events.add('out'),
  );
  return (s, r, p, events);
}

void main() {
  test('starts loading, then loggedOut when no session', () async {
    final (s, _, _, _) = await make();
    expect(s.status, AuthStatus.loading);
    await s.init();
    expect(s.status, AuthStatus.loggedOut);
  });

  test('session with a stored profile is ready and cached; onSignedIn is not fired for a restored session', () async {
    final (s, _, prefs, events) = await make(repo: FakeAuthRepository(signedIn: true, stored: sampleProfile));
    await s.init();
    expect(s.status, AuthStatus.ready);
    expect(s.profile?.nickname, 'สมศรี');
    expect(prefs.getString(cacheKey), isNotNull);
    expect(events, isEmpty);
  });

  test('session without a profile needs one (closing the app mid-onboarding)', () async {
    final repo = FakeAuthRepository(signedIn: true, stored: null);
    final (s, _, _, _) = await make(repo: repo);
    await s.init();
    expect(s.status, AuthStatus.needsProfile);
    // A second launch with the same backend state lands on the profile screen again.
    final (s2, _, _, _) = await make(repo: repo);
    await s2.init();
    expect(s2.status, AuthStatus.needsProfile);
  });

  test('offline with a cache uses it; offline without a cache is unavailable', () async {
    final cached = {cacheKey: '{"nickname":"แคช","full_name":"แคช ทดสอบ","age":40,"conditions":["โรคไต"],"consent_at":"2026-11-05T00:00:00.000Z"}'};
    final repo = FakeAuthRepository(signedIn: true)..failure = const AuthFailure(AuthFailureKind.network);
    final (s, _, _, _) = await make(repo: repo, prefs: cached);
    await s.init();
    expect(s.status, AuthStatus.ready);
    expect(s.profile?.nickname, 'แคช');

    final (s2, _, _, _) = await make(repo: FakeAuthRepository(signedIn: true)..failure = const AuthFailure(AuthFailureKind.network));
    await s2.init();
    expect(s2.status, AuthStatus.unavailable);
  });

  test('corrupt cache is ignored', () async {
    final repo = FakeAuthRepository(signedIn: true)..failure = const AuthFailure(AuthFailureKind.network);
    final (s, _, _, _) = await make(repo: repo, prefs: {cacheKey: 'not json'});
    await s.init();
    expect(s.status, AuthStatus.unavailable);
  });

  test('verifyOtp with an existing profile becomes ready and fires onSignedIn once', () async {
    final (s, repo, prefs, events) = await make(repo: FakeAuthRepository(stored: sampleProfile));
    await s.init();
    await s.verifyOtp('+66812345678', '123456');
    expect(repo.verifyCalls, 1);
    expect(s.status, AuthStatus.ready);
    expect(events, ['in:สมศรี:+66812345678']);
    expect(prefs.getString(cacheKey), isNotNull);
  });

  test('verifyOtp for a new user needs a profile', () async {
    final (s, _, _, events) = await make();
    await s.init();
    await s.verifyOtp('+66812345678', '123456');
    expect(s.status, AuthStatus.needsProfile);
    expect(events, isEmpty);
  });

  test('wrong code throws and leaves the state unchanged', () async {
    final repo = FakeAuthRepository()..failure = const AuthFailure(AuthFailureKind.invalidCode);
    final (s, _, _, _) = await make(repo: repo);
    await s.init();
    await expectLater(s.verifyOtp('+66812345678', '000000'), throwsA(isA<AuthFailure>()));
    expect(s.status, AuthStatus.loggedOut);
  });

  test('saveProfile success caches, becomes ready and fires onSignedIn', () async {
    final repo = FakeAuthRepository(signedIn: true);
    final (s, _, prefs, events) = await make(repo: repo);
    await s.init();
    await s.saveProfile(sampleProfile);
    expect(s.status, AuthStatus.ready);
    expect(repo.lastSaved?.nickname, 'สมศรี');
    expect(prefs.getString(cacheKey), isNotNull);
    expect(events, ['in:สมศรี:+66812345678']);
  });

  test('saveProfile failure throws and keeps needsProfile', () async {
    final repo = FakeAuthRepository(signedIn: true);
    final (s, _, _, events) = await make(repo: repo);
    await s.init();
    repo.failure = const AuthFailure(AuthFailureKind.network);
    await expectLater(s.saveProfile(sampleProfile), throwsA(isA<AuthFailure>()));
    expect(s.status, AuthStatus.needsProfile);
    expect(events, isEmpty);
  });

  test('signOut clears the cache and fires onSignedOut', () async {
    final (s, repo, prefs, events) = await make(repo: FakeAuthRepository(signedIn: true, stored: sampleProfile));
    await s.init();
    await s.signOut();
    expect(repo.signOutCalls, 1);
    expect(s.status, AuthStatus.loggedOut);
    expect(s.profile, isNull);
    expect(prefs.getString(cacheKey), isNull);
    expect(events, ['out']);
  });

  test('signOut still clears local state when the backend call fails', () async {
    final repo = FakeAuthRepository(signedIn: true, stored: sampleProfile);
    final (s, _, prefs, events) = await make(repo: repo);
    await s.init();
    repo.failure = const AuthFailure(AuthFailureKind.network);
    await s.signOut(); // must not throw
    expect(s.status, AuthStatus.loggedOut);
    expect(prefs.getString(cacheKey), isNull);
    expect(events, ['out']);
  });

  test('Profile.fromJson is used for the cache round-trip', () async {
    final (s, _, prefs, _) = await make(repo: FakeAuthRepository(signedIn: true, stored: sampleProfile));
    await s.init();
    final (s2, _, _, _) = await make(
      repo: FakeAuthRepository(signedIn: true)..failure = const AuthFailure(AuthFailureKind.network),
      prefs: {cacheKey: prefs.getString(cacheKey)!},
    );
    await s2.init();
    expect(s2.profile?.fullName, 'สมศรี ใจดี');
    expect(s.profile, isA<Profile>());
  });
}
