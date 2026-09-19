// SPDX-License-Identifier: AGPL-3.0-or-later
import 'lan_server_base.dart';

const supported = false;

Future<LanServer> start({required int port}) =>
    Future<LanServer>.error(UnsupportedError('LAN hosting is not supported'));
