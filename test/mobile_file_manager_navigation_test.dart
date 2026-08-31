// Mobile file navigation must consume Android Back before tab history exits.

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/state/mobile_file_manager_navigation.dart';

void main() {
  test(
    'delegates Back to the active file browser and clears cleanly',
    () async {
      final navigation = MobileFileManagerNavigation();
      var calls = 0;

      Future<bool> handleBack() async {
        calls++;
        return true;
      }

      navigation.bind(handleBack);
      expect(await navigation.handleBack(), isTrue);
      expect(calls, 1);

      navigation.clear();
      expect(await navigation.handleBack(), isFalse);
      navigation.dispose();
    },
  );
}
