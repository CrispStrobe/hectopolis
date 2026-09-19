// SPDX-License-Identifier: AGPL-3.0-or-later
import 'transport.dart';

/// A native device's opt-in WebSocket listener for one LAN game.
abstract class LanServer {
  int get port;
  String get roomSecret;
  List<String> get addresses;
  Stream<Transport> get connections;

  /// A code a second device can type. It deliberately contains no device
  /// name; unlike mDNS it broadcasts nothing to the rest of the network.
  String roomCode(String address) => '$address:$port/$roomSecret';

  Uri uriFor(String address) => Uri.parse('ws://${roomCode(address)}');

  Future<void> close();
}
