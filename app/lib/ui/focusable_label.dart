// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';

/// One spoken label for a control drawn from several parts, which a screen
/// reader can still focus.
///
/// A palette card or a gauge is an icon, a name, a number and a bar; merged
/// with `excludeSemantics` they read as one sentence instead of four
/// fragments. But `excludeSemantics` also drops the focus flags the
/// `InkWell` inside would have published, and on the web a screen reader
/// follows the browser's focus, which only lands on nodes that carry them:
/// Tab moved Flutter's focus through the cards while the screen reader sat
/// on the last control that had them, saying nothing. This owns the focus
/// node, hands it to [builder] for the `InkWell`, and puts the flags back on
/// the merged label.
class FocusableLabel extends StatefulWidget {
  const FocusableLabel({
    super.key,
    required this.label,
    this.hint,
    this.selected,
    required this.onTap,
    required this.builder,
  });

  final String label;
  final String? hint;
  final bool? selected;
  final VoidCallback onTap;

  /// Builds the control; pass the node to its `InkWell` as `focusNode`.
  final Widget Function(BuildContext context, FocusNode focusNode) builder;

  @override
  State<FocusableLabel> createState() => _FocusableLabelState();
}

class _FocusableLabelState extends State<FocusableLabel> {
  late final FocusNode _node = FocusNode(debugLabel: widget.label)
    ..addListener(_onFocusChanged);

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      hint: widget.hint,
      button: true,
      selected: widget.selected,
      container: true,
      excludeSemantics: true,
      onTap: widget.onTap,
      focusable: true,
      focused: _node.hasFocus,
      onFocus: _node.requestFocus,
      child: widget.builder(context, _node),
    );
  }
}
