// Remote configuration tests pin polling-interval JSON and immutable updates.
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/remote_storage_config.dart';

void main() {
  test('remote poll interval survives JSON parsing and copyWith', () {
    final config = RemoteStorageConfig.fromJson(<String, dynamic>{
      'mount_remote_poll_seconds': 15,
    });

    expect(config.mountRemotePollSeconds, 15);
    expect(
      config.copyWith(mountRemotePollSeconds: 30).toJson(),
      containsPair('mountRemotePollSeconds', 30),
    );
  });

  test('invalid remote poll interval falls back to five seconds', () {
    final config = RemoteStorageConfig.fromJson(<String, dynamic>{
      'mountRemotePollSeconds': 0,
    });

    expect(config.effectiveMountRemotePollSeconds, 5);
  });

  test('profile identity survives JSON parsing and copyWith', () {
    final config = RemoteStorageConfig.fromJson(<String, dynamic>{
      'profileId': 'stable-profile-id',
    });

    expect(config.profileId, 'stable-profile-id');
    expect(
      config.copyWith(displayName: 'renamed').toJson(),
      containsPair('profileId', 'stable-profile-id'),
    );
  });
}
