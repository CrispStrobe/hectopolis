// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stadtbau/game/lan_session.dart';
import 'package:stadtbau_sim/stadtbau_sim.dart';

void main() {
  test('the app session hosts and joins a real loopback game', () async {
    final host = await LanSession.host(playerName: 'Ada', width: 8, height: 8);
    final guest = await LanSession.join(
      playerName: 'Linus',
      roomCode: host.server!.roomCode('127.0.0.1'),
    );
    addTearDown(() async {
      await guest.close();
      await host.close();
    });

    await _until(
      () =>
          host.controller.players.length == 2 &&
          guest.controller.simulation != null,
    );
    expect(guest.controller.resumeToken, matches(RegExp(r'^[0-9a-f]{32}$')));

    host.controller.splitIntoStrips();
    guest.controller.setReady(ready: true);
    await _until(() => host.controller.canStart);
    host.controller.start();
    await _until(() => guest.controller.started);

    host.controller.endTurn();
    await _until(() => guest.controller.isMyTurn);
    guest.controller.request(const PlaceTile(6, 2, TileType.park));
    await _until(
      () =>
          host.controller.simulation!.state.tileAt(6, 2) == TileType.park &&
          guest.controller.simulation!.state.hash() ==
              host.controller.simulation!.state.hash(),
    );
  });
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
