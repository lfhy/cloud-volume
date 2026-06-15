// Web entry starts only the primary app shell.

import 'package:flutter/widgets.dart';
import 'package:remote_storage/app/remote_storage_app.dart';

Future<void> runRemoteStorageEntry(List<String> args) async {
  runApp(const RemoteStorageApp());
}
