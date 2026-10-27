// SPDX-License-Identifier: AGPL-3.0-or-later
// Runs the Hectopolis relay. See docs/relay-hosting.md.
import 'dart:async';
import 'dart:io';

import 'package:stadtbau_relay/stadtbau_relay.dart';

const _usage = '''
Usage: relay [--address 127.0.0.1] [--port 8080] [--max-rooms 200]

Serves plain ws:// on the given address. Put it behind a reverse proxy that
terminates TLS: the game connects to a relay only over wss://.
The port may also come from the PORT environment variable.''';

Future<void> main(List<String> args) async {
  String option(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }
  final port = int.tryParse(
    option('port', Platform.environment['PORT'] ?? '8080'),
  );
  final maxRooms = int.tryParse(option('max-rooms', '200'));
  if (port == null || maxRooms == null) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  final server = await RelayServer.start(
    address: option('address', '127.0.0.1'),
    port: port,
    limits: RelayLimits(maxRooms: maxRooms),
  );
  stdout.writeln('hectopolis relay listening on port ${server.port}');

  // Aggregate counts only: no room ids, no addresses, no frame contents.
  final status = Timer.periodic(const Duration(minutes: 10), (_) {
    stdout.writeln(
      'rooms ${server.rooms.roomCount}, guests ${server.rooms.guestCount}',
    );
  });
  final stop = Completer<void>();
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) {
      if (!stop.isCompleted) stop.complete();
    });
  }
  await stop.future;
  status.cancel();
  await server.close();
}
