import 'package:flutter/widgets.dart';
import 'package:remote_storage/app/app_entry.dart';
import 'package:remote_storage/platform/platform_bootstrap.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializePlatformServices();
  await runRemoteStorageEntry(args);
}
