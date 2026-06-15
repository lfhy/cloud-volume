// Update service tests keep local and GitHub release version comparisons stable.

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/services/app_update_service.dart';

void main() {
  test('compareVersionLabels detects newer GitHub release tags', () {
    expect(compareVersionLabels('v1.2.2', 'v1.2.3'), lessThan(0));
    expect(compareVersionLabels('1.2.3+7', 'v1.2.3'), 0);
    expect(compareVersionLabels('1.3.0', 'v1.2.9'), greaterThan(0));
  });

  test('compareVersionLabels handles prerelease ordering', () {
    expect(compareVersionLabels('v1.2.3-beta.1', 'v1.2.3'), lessThan(0));
    expect(
      compareVersionLabels('v1.2.3-beta.2', 'v1.2.3-beta.1'),
      greaterThan(0),
    );
  });

  test('compareVersionLabels returns null for dev builds', () {
    expect(compareVersionLabels('dev', 'v1.2.3'), isNull);
  });
}
