// SPDX-License-Identifier: AGPL-3.0-or-later
// T-602: conditional facade keeps server-only dart:io out of web builds.
import 'lan_server_base.dart';
import 'lan_server_stub.dart'
    if (dart.library.io) 'lan_server_io.dart'
    as implementation;

export 'lan_server_base.dart';

bool get lanHostingSupported => implementation.supported;

Future<LanServer> startLanServer({int port = 0}) =>
    implementation.start(port: port);

/// Parses the code shown by a host. A full ws:// URL is accepted too, which
/// makes the same field useful for development and manual IP entry.
Uri parseRoomCode(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) throw const FormatException('empty room code');
  final withScheme = trimmed.contains('://') ? trimmed : 'ws://$trimmed';
  final uri = Uri.parse(withScheme);
  if (uri.scheme != 'ws' && uri.scheme != 'wss') {
    throw const FormatException('room code must use ws or wss');
  }
  if (uri.host.isEmpty || !uri.hasPort || uri.pathSegments.length != 1) {
    throw const FormatException('expected host:port/room');
  }
  return uri;
}
