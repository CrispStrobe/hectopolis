// SPDX-License-Identifier: AGPL-3.0-or-later
/// Co-operative play for Hectopolis: a versioned message protocol, an
/// authoritative host and a mirroring client (T-601).
///
/// Transport-agnostic on purpose. Nothing here opens a socket; see
/// `src/transport.dart` for why that line is drawn here.
library;

export 'src/client.dart';
export 'src/host.dart';
export 'src/protocol.dart';
export 'src/transport.dart';
