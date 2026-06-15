// Desktop bootstrap installs the SQLite FFI factory before Flutter renders.

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> initializePlatformServices() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}
