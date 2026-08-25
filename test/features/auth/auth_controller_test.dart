import 'dart:async';

import 'package:escrow/core/network/api_exception.dart';
import 'package:escrow/core/providers.dart';
import 'package:escrow/features/auth/application/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late FakeTokenStore tokens;
  late FakeAuthRepository repo;
  late FakeBiometricService biometrics;

  ProviderContainer makeContainer() {
    final c = ProviderContainer(overrides: [
      tokenStoreProvider.overrideWithValue(tokens),
      authRepositoryProvider.overrideWithValue(repo),
      biometricServiceProvider.overrideWithValue(biometrics),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    tokens = FakeTokenStore();
    repo = FakeAuthRepository();
    biometrics = FakeBiometricService();
  });

  test('cold start with no stored token → unauthenticated', () async {
    final c = makeContainer();
    final state = await c.read(authControllerProvider.future);
    expect(state.isAuthenticated, isFalse);
  });

  test('cold start with a stored token → restores the session', () async {
    await tokens.save(access: 'a', refresh: 'r');
    final c = makeContainer();
    final state = await c.read(authControllerProvider.future);
    expect(state.isAuthenticated, isTrue);
    expect(state.user?.fullName, 'Amara Okafor');
  });

  test('login success → authenticated and tokens persisted', () async {
    final c = makeContainer();
    await c.read(authControllerProvider.future);
    await c
        .read(authControllerProvider.notifier)
        .login(identifier: 'amara', pin: '123456');
    expect(c.read(authControllerProvider).value!.isAuthenticated, isTrue);
    expect(tokens.refreshToken, 'r');
  });

  test('login failure → throws and stays unauthenticated', () async {
    repo.failLogin = true;
    final c = makeContainer();
    await c.read(authControllerProvider.future);
    await expectLater(
      c.read(authControllerProvider.notifier).login(identifier: 'x', pin: '000000'),
      throwsA(isA<ApiException>()),
    );
    expect(c.read(authControllerProvider).value!.isAuthenticated, isFalse);
    expect(tokens.refreshToken, isNull);
  });

  test('biometric enabled + stored session → locked on launch', () async {
    await tokens.save(access: 'a', refresh: 'r');
    biometrics.enabled = true;
    final c = makeContainer();
    final state = await c.read(authControllerProvider.future);
    expect(state.isLocked, isTrue);
    expect(state.isAuthenticated, isFalse);
  });

  test('unlock restores the locked session', () async {
    await tokens.save(access: 'a', refresh: 'r');
    biometrics.enabled = true;
    final c = makeContainer();
    await c.read(authControllerProvider.future);
    await c.read(authControllerProvider.notifier).unlock();
    expect(c.read(authControllerProvider).value!.isAuthenticated, isTrue);
  });

  test(
      'warm re-lock: unlock() reveals instantly without waiting on /users/me, '
      'then confirms it in the background', () async {
    await tokens.save(access: 'a', refresh: 'r');
    final c = makeContainer();
    await c.read(authControllerProvider.future); // authenticated (biometrics off)
    final notifier = c.read(authControllerProvider.notifier);

    biometrics.enabled = true;
    await notifier.relockIfBiometricEnabled();
    expect(c.read(authControllerProvider).value!.isLocked, isTrue);

    // Freeze /users/me — if unlock() waited on it, this await would hang.
    repo.meGate = Completer<void>();
    final matched = await notifier.unlock();

    expect(matched, isTrue);
    expect(
      c.read(authControllerProvider).value!.isAuthenticated,
      isTrue,
      reason: 'revealed using the session already held, not /users/me',
    );

    // Let the background revalidation actually resolve, and confirm it
    // still ran (not skipped) — stays authenticated once /users/me confirms
    // the token is fine.
    repo.meGate!.complete();
    await pumpEventQueue();
    expect(c.read(authControllerProvider).value!.isAuthenticated, isTrue);
  });

  test(
      'warm re-lock: a dead token found by the background revalidation still '
      'signs out, just a beat after the instant reveal', () async {
    await tokens.save(access: 'a', refresh: 'r');
    final c = makeContainer();
    await c.read(authControllerProvider.future);
    final notifier = c.read(authControllerProvider.notifier);

    biometrics.enabled = true;
    await notifier.relockIfBiometricEnabled();

    repo.meGate = Completer<void>();
    repo.failMe = true; // the background /users/me will now 401
    final matched = await notifier.unlock();

    expect(matched, isTrue);
    expect(
      c.read(authControllerProvider).value!.isAuthenticated,
      isTrue,
      reason: 'still revealed optimistically before the token check lands',
    );

    repo.meGate!.complete();
    await pumpEventQueue();
    expect(c.read(authControllerProvider).value!.isAuthenticated, isFalse);
    expect(tokens.refreshToken, isNull);
  });

  test('logout clears tokens and returns to unauthenticated', () async {
    final c = makeContainer();
    await c.read(authControllerProvider.future);
    await c
        .read(authControllerProvider.notifier)
        .login(identifier: 'amara', pin: '123456');
    await c.read(authControllerProvider.notifier).logout();
    expect(c.read(authControllerProvider).value!.isAuthenticated, isFalse);
    expect(tokens.refreshToken, isNull);
  });
}
