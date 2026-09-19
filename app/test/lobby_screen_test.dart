// SPDX-License-Identifier: AGPL-3.0-or-later
// T-603: the lobby, driven by a real host and a real guest over the in-memory
// transport. No socket is involved, which is the whole reason this can be a
// widget test at all.
import 'dart:async';

import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:stadtbau/game/session_controller.dart';
import 'package:stadtbau/l10n/generated/app_localizations.dart';
import 'package:stadtbau/ui/lobby_screen.dart';
import 'package:stadtbau_net/stadtbau_net.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

Widget _app(
  SessionController c, {
  VoidCallback? onStart,
  List<String> roomCodes = const [],
}) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: LobbyScreen(
    controller: c,
    onStart: onStart ?? () {},
    roomCodes: roomCodes,
  ),
);

/// A host controller and a guest controller, connected and settled, plus the
/// guest's end of the wire so a test can pull the plug on it.
Future<
  ({
    SessionController host,
    SessionController guest,
    InMemoryTransport guestWire,
  })
>
_pair() async {
  final host = SessionController.host(
    simulation: Simulation(
      state: WorldState.empty(width: 16, height: 16, budgetKEur: 10000),
    ),
    playerName: 'Ada',
  );
  final (hostEnd, guestEnd) = InMemoryTransport.pair();
  host.accept(hostEnd);
  final guest = SessionController.join(
    transport: guestEnd,
    playerName: 'Linus',
  );
  await InMemoryTransport.settle();
  return (host: host, guest: guest, guestWire: guestEnd);
}

void main() {
  testWidgets('the host can share its room code as text and QR', (
    tester,
  ) async {
    final s = await _pair();
    addTearDown(() async {
      await s.host.close();
      await s.guest.close();
    });
    const code = '192.168.1.20:43123/test-secret';
    await tester.pumpWidget(_app(s.host, roomCodes: const [code]));
    await tester.pumpAndSettle();

    expect(find.text(code), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('the host sees a guest arrive', (tester) async {
    final s = await _pair();
    addTearDown(() async {
      await s.host.close();
      await s.guest.close();
    });
    await tester.pumpWidget(_app(s.host));
    await tester.pumpAndSettle();
    expect(find.text('Ada (host) (you)'), findsOneWidget);
    expect(find.text('Linus'), findsOneWidget);
    expect(find.text('No district yet'), findsNWidgets(2));
  });

  testWidgets('dividing the map gives every player their own columns', (
    tester,
  ) async {
    final s = await _pair();
    addTearDown(() async {
      await s.host.close();
      await s.guest.close();
    });
    await tester.pumpWidget(_app(s.host));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Divide the map'));
    await InMemoryTransport.settle();
    await tester.pumpAndSettle();
    // 16 columns, two players: 1-8 and 9-16, with nothing unassigned.
    expect(find.text('Columns 1–8'), findsOneWidget);
    expect(find.text('Columns 9–16'), findsOneWidget);
  });

  testWidgets('the host cannot start until the guest is ready', (tester) async {
    final s = await _pair();
    addTearDown(() async {
      await s.host.close();
      await s.guest.close();
    });
    await tester.pumpWidget(_app(s.host));
    await tester.pumpAndSettle();
    final start = find.widgetWithText(FilledButton, 'Start building');
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    expect(find.text('Everyone has to be ready first.'), findsOneWidget);

    s.guest.setReady(ready: true);
    await InMemoryTransport.settle();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
  });

  testWidgets('a guest toggles ready and the host sees it', (tester) async {
    final s = await _pair();
    addTearDown(() async {
      await s.host.close();
      await s.guest.close();
    });
    await tester.pumpWidget(_app(s.guest));
    await tester.pumpAndSettle();
    expect(find.text('Not ready'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await InMemoryTransport.settle();
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
    expect(s.host.players.where((p) => p.ready), hasLength(1));
  });

  testWidgets('starting the game calls back, for the host and the guest', (
    tester,
  ) async {
    final s = await _pair();
    addTearDown(() async {
      await s.host.close();
      await s.guest.close();
    });
    var guestStarted = false;
    await tester.pumpWidget(_app(s.guest, onStart: () => guestStarted = true));
    await tester.pumpAndSettle();
    s.host.start();
    await InMemoryTransport.settle();
    await tester.pumpAndSettle();
    expect(
      guestStarted,
      isTrue,
      reason: 'a guest learns from the lobby update, not from a tap',
    );
  });

  testWidgets('a refused join explains itself instead of hanging', (
    tester,
  ) async {
    final host = SessionController.host(
      simulation: Simulation(
        state: WorldState.empty(width: 16, height: 16, budgetKEur: 1000),
      ),
      playerName: 'Ada',
      maxPlayers: 1, // only the host fits
    );
    final (hostEnd, guestEnd) = InMemoryTransport.pair();
    host.accept(hostEnd);
    final guest = SessionController.join(
      transport: guestEnd,
      playerName: 'Linus',
    );
    await InMemoryTransport.settle();
    addTearDown(() async {
      await host.close();
      await guest.close();
    });
    await tester.pumpWidget(_app(guest));
    await tester.pumpAndSettle();
    expect(find.textContaining('the session is full'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('a held seat is shown as held, and can be given up', (
    tester,
  ) async {
    final s = await _pair();
    final guestId = s.guest.playerId!;
    s.host.start();
    await InMemoryTransport.settle();
    // Pull the plug on the wire rather than tearing the controller down:
    // that is what a dropped connection actually is, and awaiting a session
    // teardown inside a `testWidgets` body stalls under the faked clock.
    // Closing a transport outside message delivery does its work
    // synchronously, so the host has already noticed by the next line.
    unawaited(s.guestWire.close());
    await InMemoryTransport.settle();
    addTearDown(s.host.close);
    addTearDown(s.guest.close);

    await tester.pumpWidget(_app(s.host));
    await tester.pumpAndSettle();
    expect(find.text('Connection lost — seat held'), findsOneWidget);
    await tester.tap(find.text('Give up this seat'));
    await InMemoryTransport.settle();
    await tester.pumpAndSettle();
    expect(find.text('Linus'), findsNothing);
    expect(s.host.players.map((p) => p.id), isNot(contains(guestId)));
  });
}
