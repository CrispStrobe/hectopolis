// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stadtbau_net/stadtbau_net.dart';

import '../game/game_controller.dart';
import '../game/lan_session.dart';
import '../l10n/generated/app_localizations.dart';
import 'game_screen.dart';
import 'lobby_screen.dart';

/// Manual, non-broadcast LAN entry point (T-602).
class CoopSetupScreen extends StatefulWidget {
  const CoopSetupScreen({
    super.key,
    required this.gameController,
    required this.onLocaleToggle,
  });

  final GameController gameController;
  final VoidCallback onLocaleToggle;

  @override
  State<CoopSetupScreen> createState() => _CoopSetupScreenState();
}

class _CoopSetupScreenState extends State<CoopSetupScreen> {
  final _name = TextEditingController();
  final _room = TextEditingController();
  bool _busy = false;
  bool _failed = false;
  bool _gameOpen = false;

  @override
  void dispose() {
    _name.dispose();
    _room.dispose();
    super.dispose();
  }

  bool get _hasName => _name.text.trim().isNotEmpty;

  Future<void> _host() async {
    if (!_hasName || _busy) return;
    await _start(() => LanSession.host(playerName: _name.text.trim()));
  }

  Future<void> _join() async {
    if (!_hasName || _room.text.trim().isEmpty || _busy) return;
    await _start(
      () =>
          LanSession.join(playerName: _name.text.trim(), roomCode: _room.text),
    );
  }

  Future<void> _start(Future<LanSession> Function() create) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    LanSession? session;
    try {
      session = await create();
      if (!mounted) {
        await session.close();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LobbyScreen(
            controller: session!.controller,
            roomCodes: session.roomCodes,
            onStart: () => unawaited(_openGame(session!)),
          ),
        ),
      );
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      widget.gameController.endCooperative();
      if (session != null) await session.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openGame(LanSession session) async {
    if (_gameOpen || !mounted) return;
    _gameOpen = true;
    widget.gameController.startCooperative(
      session.controller,
      reconnect: session.canReconnect ? session.reconnect : null,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          controller: widget.gameController,
          onLocaleToggle: widget.onLocaleToggle,
        ),
      ),
    );
    widget.gameController.endCooperative();
    _gameOpen = false;
    // The lobby is still the top route. Leaving it completes [_start], which
    // owns and closes the listener and every accepted socket.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.coopSetupTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l10n.coopDirectPrivacy),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: l10n.coopPlayerName,
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: lanHostingSupported && _hasName && !_busy
                    ? _host
                    : null,
                icon: const Icon(Icons.wifi_tethering),
                label: Text(l10n.coopHost),
              ),
              if (!lanHostingSupported)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(l10n.coopHostingUnsupported),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(),
              ),
              TextField(
                controller: _room,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: l10n.coopRoomCode,
                  border: const OutlineInputBorder(),
                ),
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _join(),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _hasName && _room.text.trim().isNotEmpty && !_busy
                    ? _join
                    : null,
                icon: const Icon(Icons.login),
                label: Text(l10n.coopJoin),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l10n.coopConnectionFailed,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
