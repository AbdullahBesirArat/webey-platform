import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webey_mobile/shared/services/api_client.dart';

void installNoNetworkHttpOverrides() {
  final previousOverrides = HttpOverrides.current;
  final previousDebugNetworkFlag = ApiClient.debugDisableNetworkForTests;

  setUpAll(() {
    ApiClient.debugDisableNetworkForTests = true;
    HttpOverrides.global = _NoNetworkHttpOverrides();
  });

  tearDownAll(() {
    ApiClient.debugDisableNetworkForTests = previousDebugNetworkFlag;
    HttpOverrides.global = previousOverrides;
  });
}

Future<void> runWithNoNetwork(FutureOr<void> Function() body) async {
  final previousDebugNetworkFlag = ApiClient.debugDisableNetworkForTests;
  ApiClient.debugDisableNetworkForTests = true;

  try {
    await HttpOverrides.runZoned(() async {
      await body();
    }, createHttpClient: _createNoNetworkHttpClient);
  } finally {
    ApiClient.debugDisableNetworkForTests = previousDebugNetworkFlag;
  }
}

HttpClient _createNoNetworkHttpClient(SecurityContext? context) {
  stderr.writeln(webeyNetworkDisabledMessage);
  throw UnsupportedError(webeyNetworkDisabledMessage);
}

class _NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _createNoNetworkHttpClient(context);
  }
}
