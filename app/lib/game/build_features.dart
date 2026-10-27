// SPDX-License-Identifier: AGPL-3.0-or-later

/// Whether this build can play co-op through an internet relay (T-606).
///
/// A compile-time switch rather than a setting, so a build without it carries
/// none of the code: every use below is a constant branch the compiler drops.
///
///     flutter build ipa --dart-define=HECTOPOLIS_RELAY=false
///
/// The App Store builds (iOS and macOS) leave relays out for now, and
/// `tools/check.sh store-flags` fails if either release workflow stops
/// passing the switch. Without it the co-op screen offers the local network
/// only, a relay code is refused, and the privacy copy says what it said
/// before relays existed.
const relayEnabled = bool.fromEnvironment(
  'HECTOPOLIS_RELAY',
  defaultValue: true,
);

/// Whether About's "Our apps" also lists apps that are only in TestFlight or
/// not out yet. Off for now: the gallery shows apps that are live in a store.
///
///     flutter build web --dart-define=HECTOPOLIS_SHOWCASE_BETAS=true
const showcaseBetaOnlyApps = bool.fromEnvironment('HECTOPOLIS_SHOWCASE_BETAS');
