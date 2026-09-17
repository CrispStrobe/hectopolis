// SPDX-License-Identifier: AGPL-3.0-or-later
// T-601: how messages travel, kept separate from what they mean.
//
// There is deliberately no socket in this package. [Transport] is an
// interface over "send a string, receive strings, close", and the only
// implementation here is an in-memory pair used by the tests. The WebSocket
// transport belongs with discovery (T-602), because opening a listening
// socket is the point at which the promise on the About screen -- "no network
// requests while you play" -- has to be restated for an opt-in LAN mode. It
// would be wrong to smuggle that in under a protocol task, and
// `tools/privacy_audit.sh` fails the build if any first-party code reaches
// for a networking API, which is exactly the guard that should hold until the
// decision is taken openly.
import 'dart:async';

/// A bidirectional, ordered, message-oriented channel.
///
/// Ordering is required: the host's [Applied] messages define the order in
/// which commands hit the simulation, so a transport that reorders would make
/// clients diverge. Delivery need not be reliable -- a dropped message shows
/// up as a hash mismatch and is repaired by a snapshot -- but it must not
/// deliver out of order.
abstract class Transport {
  /// Messages arriving from the peer, as raw text.
  Stream<String> get incoming;

  /// Sends one message. Must preserve order with earlier calls.
  void send(String message);

  /// Closes this end. [incoming] completes; further [send] calls are ignored.
  Future<void> close();

  /// Whether [close] has been called or the peer went away.
  bool get isClosed;
}

/// Two transports wired to each other, with no I/O at all.
///
/// Used by the tests to run a real host and real clients in one isolate. It is
/// also the shape a future in-process "hotseat" mode would use, so it is not
/// test-only scaffolding.
class InMemoryTransport implements Transport {
  InMemoryTransport._();

  /// Creates a connected pair.
  static (InMemoryTransport, InMemoryTransport) pair() {
    final a = InMemoryTransport._();
    final b = InMemoryTransport._();
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  final StreamController<String> _in =
      StreamController<String>.broadcast(sync: true);
  InMemoryTransport? _peer;
  bool _closed = false;

  /// Messages this end refused to deliver because it was closed. Kept so a
  /// test can assert that nothing was silently dropped.
  final List<String> dropped = [];

  /// Messages sent but not yet delivered, across every pair.
  ///
  /// Delivery is deferred by one microtask (see [send]), so a test needs to
  /// know when the exchange has finished rather than guessing at a number of
  /// pumps. [settle] uses this.
  static int _inFlight = 0;

  /// Completes once every message sent so far has been delivered, including
  /// the ones the handlers sent in response. A resync is three hops -- tick,
  /// resync request, snapshot -- so "await one microtask" is not enough.
  static Future<void> settle() async {
    var guard = 0;
    while (_inFlight > 0) {
      await Future<void>.delayed(Duration.zero);
      if (++guard > 10000) {
        throw StateError('in-memory transport never settled: '
            '$_inFlight message(s) still in flight');
      }
    }
  }

  @override
  Stream<String> get incoming => _in.stream;

  @override
  bool get isClosed => _closed;

  @override
  void send(String message) {
    final peer = _peer;
    if (_closed || peer == null || peer._closed) {
      dropped.add(message);
      return;
    }
    // Delivered from a microtask, not inline. Inline delivery made the whole
    // exchange re-entrant: a host broadcast reached a client, whose hash
    // check answered with a resync request, which the host tried to answer
    // while its own controller was still firing -- "Cannot fire new event".
    // No socket behaves that way, and a protocol that only works when its
    // transport is synchronous is not a protocol. Microtasks are FIFO, so
    // ordering, which the sessions do rely on, is preserved.
    _inFlight++;
    scheduleMicrotask(() {
      _inFlight--;
      if (!peer._closed && !peer._in.isClosed) peer._in.add(message);
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final peer = _peer;
    _peer = null;
    peer?._peer = null;
    // Deferred on purpose. Closing a connection from inside a message handler
    // is ordinary -- a host rejecting a `hello` does exactly that -- and a
    // synchronous broadcast controller cannot be closed while it is
    // delivering an event ("Cannot fire new event"). A socket's close is
    // asynchronous for the same reason, so this matches the real transport
    // rather than working around the fake one.
    await Future<void>.delayed(Duration.zero);
    await _in.close();
    // Closing one end completes the other end's stream, the way a TCP FIN
    // does. Without this a host never learns that a client is gone.
    if (peer != null && !peer._closed) {
      peer._closed = true;
      await peer._in.close();
    }
  }
}
