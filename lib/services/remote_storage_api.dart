// Platform-specific API implementations stay behind a single import surface.

import 'package:remote_storage/services/remote_storage_gateway.dart';

import 'remote_storage_api_desktop.dart'
    if (dart.library.html) 'remote_storage_api_web.dart' as impl;

export 'remote_storage_gateway.dart';

Future<RemoteStorageGateway> defaultRemoteStorageApiFactory() {
  return impl.RemoteStorageApi.bootstrap();
}
