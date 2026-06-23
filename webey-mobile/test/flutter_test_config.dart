import 'dart:async';

import 'helpers/no_network_http_overrides.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await runWithNoNetwork(testMain);
}
