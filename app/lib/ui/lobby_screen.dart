// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:stadtbau_net/stadtbau_net.dart';

import '../game/session_controller.dart';
import '../l10n/generated/app_localizations.dart';

/// The lobby of a co-operative session: who is here, which part of the map is
/// theirs, and whether everyone is ready (T-603).
///
/// [SessionController] drives both this screen and the game screen. Native
/// hosts can also provide room codes, which are rendered as text and QR codes
/// so guests can join without discovery broadcasts.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({
    super.key,
    required this.controller,
    required this.onStart,
    this.roomCodes = const [],
  });

  final SessionController controller;
  final List<String> roomCodes;

  /// Called when the host starts the game, or when a guest is told it has
  /// started. The caller owns navigation into the game screen.
  final VoidCallback onStart;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _ready = false;
  bool _startedHandled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    // A guest learns the game began from the lobby update, not from a tap.
    if (widget.controller.started && !_startedHandled) {
      _startedHandled = true;
      widget.onStart();
    }
  }

  String _rejectText(AppLocalizations l10n, RejectReason reason) =>
      switch (reason) {
        RejectReason.sessionFull => l10n.lobbyRejectFull,
        RejectReason.alreadyStarted => l10n.lobbyRejectStarted,
        RejectReason.nameTaken => l10n.lobbyRejectName,
        RejectReason.unknownSeat => l10n.lobbyRejectSeat,
        RejectReason.protocolMismatch => l10n.lobbyRejectProtocol,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = widget.controller;
    final rejected = c.rejectReason;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.lobbyTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (rejected != null)
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      l10n.lobbyRejected(_rejectText(l10n, rejected)),
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                )
              else ...[
                if (widget.roomCodes.isNotEmpty) ...[
                  Text(l10n.coopRoomInstructions),
                  const SizedBox(height: 12),
                  Center(
                    child: QrImageView(
                      data: widget.roomCodes.first,
                      size: 176,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  for (final code in widget.roomCodes)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.key),
                      title: Text(l10n.coopRoomCodeLabel),
                      subtitle: SelectableText(code),
                      trailing: IconButton(
                        tooltip: l10n.coopCopyCode,
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.coopCodeCopied)),
                          );
                        },
                      ),
                    ),
                  const Divider(),
                ],
                Text(l10n.lobbyPlayers, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                for (final p in c.players) _PlayerRow(p: p, controller: c),
                if (c.players.length < 2)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      l10n.lobbyWaiting,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  l10n.lobbyDistrictsExplain,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (c.isHost) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.grid_view),
                    label: Text(l10n.lobbySplitDistricts),
                    onPressed: c.players.isEmpty ? null : c.splitIntoStrips,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: Text(l10n.lobbyStart),
                    onPressed: c.canStart
                        ? () {
                            c.start();
                            widget.onStart();
                          }
                        : null,
                  ),
                  if (!c.canStart)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        l10n.lobbyStartHint,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ] else
                  SwitchListTile(
                    value: _ready,
                    title: Text(_ready ? l10n.lobbyReady : l10n.lobbyNotReady),
                    onChanged: (v) {
                      setState(() => _ready = v);
                      c.setReady(ready: v);
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.p, required this.controller});

  final PlayerInfo p;
  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isMe = p.id == controller.playerId;
    final d = p.district;
    final subtitle = !p.connected
        ? l10n.lobbyDisconnected
        : d == null
        ? l10n.lobbyNoDistrict
        : l10n.lobbyDistrictOf(d.x + 1, d.x + d.width);
    return ListTile(
      dense: true,
      leading: Icon(
        p.connected ? Icons.person : Icons.person_off,
        color: p.connected ? null : theme.colorScheme.outline,
      ),
      title: Text(
        [
          p.name,
          if (p.isHost) '(${l10n.lobbyHostLabel})',
          if (isMe) '(${l10n.lobbyYou})',
        ].join(' '),
      ),
      subtitle: Text(subtitle),
      trailing: !p.connected && controller.isHost
          ? TextButton(
              onPressed: () => controller.releaseSeat(p.id),
              child: Text(l10n.lobbyReleaseSeat),
            )
          : p.connected && !p.isHost
          ? Icon(
              p.ready ? Icons.check_circle : Icons.radio_button_unchecked,
              color: p.ready ? theme.colorScheme.primary : null,
            )
          : null,
    );
  }
}
