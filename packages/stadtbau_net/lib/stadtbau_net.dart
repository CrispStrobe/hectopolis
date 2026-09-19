// SPDX-License-Identifier: AGPL-3.0-or-later
/// Co-operative play for Hectopolis: a versioned message protocol, an
/// authoritative host and a mirroring client (T-601).
///
/// Session rules remain transport-agnostic. T-602 adds an opt-in LAN
/// WebSocket at the package boundary; the simulation package stays pure.
library;

export 'src/client.dart';
export 'src/host.dart';
export 'src/lan_server.dart';
export 'src/protocol.dart';
export 'src/transport.dart';
export 'src/websocket_transport.dart';
