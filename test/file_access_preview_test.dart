// Preview source tests keep Markdown's mobile-safe byte ceiling before cache IO.

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/services/file_access_service.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';

void main() {
  test(
    'large Markdown is rejected after head and before cache download',
    () async {
      final gateway = _PreviewGateway(
        const ObjectInfo(
          key: 'docs/large.md',
          size: 8 * 1024 * 1024 + 1,
          isDir: false,
        ),
      );

      await expectLater(
        FileAccessService.instance.preparePreviewSource(
          api: gateway,
          config: RemoteStorageConfig.empty(),
          bucket: 'documents',
          object: const ObjectInfo(
            key: 'docs/large.md',
            size: 8 * 1024 * 1024 + 1,
            isDir: false,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('8 MB'),
          ),
        ),
      );
      expect(gateway.headCalls, 1);
    },
  );
}

class _PreviewGateway extends Fake implements RemoteStorageGateway {
  _PreviewGateway(this.object);

  final ObjectInfo object;
  int headCalls = 0;

  @override
  Future<ObjectInfo> headObject(
    RemoteStorageConfig config,
    String bucket,
    String key,
  ) async {
    headCalls++;
    return object;
  }
}
