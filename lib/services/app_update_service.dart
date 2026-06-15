// 应用更新服务：从 GitHub Releases 读取最新版本，并集中处理版本号比较。

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:remote_storage/utils/app_runtime_version.dart';

const String kAppLatestReleaseApiUrl =
    'https://api.github.com/repos/lfhy/cloud-volume/releases/latest';
const String kAppLatestReleasePageUrl =
    'https://github.com/lfhy/cloud-volume/releases/latest';

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseUrl,
    required this.updateAvailable,
    required this.comparable,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final String releaseUrl;
  final bool updateAvailable;
  final bool comparable;
}

class AppUpdateService {
  AppUpdateService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Future<AppUpdateCheckResult> checkLatestRelease({
    String currentVersion = kAppRuntimeVersion,
  }) async {
    final response = await _client
        .get(
          Uri.parse(kAppLatestReleaseApiUrl),
          headers: const <String, String>{
            'accept': 'application/vnd.github+json',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppUpdateException('GitHub 返回 HTTP ${response.statusCode}');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw const AppUpdateException('GitHub 返回内容格式不正确');
    }

    final latestVersion = payload['tag_name']?.toString().trim() ?? '';
    if (latestVersion.isEmpty) {
      throw const AppUpdateException('GitHub Release 缺少版本号');
    }

    final releaseUrl =
        payload['html_url']?.toString().trim() ?? kAppLatestReleasePageUrl;
    final releaseName = payload['name']?.toString().trim() ?? latestVersion;
    final comparison = compareVersionLabels(currentVersion, latestVersion);

    return AppUpdateCheckResult(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      releaseName: releaseName.isEmpty ? latestVersion : releaseName,
      releaseUrl: releaseUrl.isEmpty ? kAppLatestReleasePageUrl : releaseUrl,
      updateAvailable: comparison != null && comparison < 0,
      comparable: comparison != null,
    );
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

int? compareVersionLabels(String currentVersion, String latestVersion) {
  final current = _ParsedVersion.tryParse(currentVersion);
  final latest = _ParsedVersion.tryParse(latestVersion);
  if (current == null || latest == null) {
    return null;
  }
  return current.compareTo(latest);
}

class _ParsedVersion implements Comparable<_ParsedVersion> {
  const _ParsedVersion({required this.core, required this.prerelease});

  final List<int> core;
  final List<String> prerelease;

  static _ParsedVersion? tryParse(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
    if (normalized.isEmpty) {
      return null;
    }
    final withoutBuild = normalized.split('+').first;
    final pieces = withoutBuild.split('-');
    final coreParts = pieces.first.split('.');
    if (coreParts.isEmpty) {
      return null;
    }
    final core = <int>[];
    for (final part in coreParts) {
      if (part.isEmpty || int.tryParse(part) == null) {
        return null;
      }
      core.add(int.parse(part));
    }
    return _ParsedVersion(
      core: core,
      prerelease: pieces.length > 1
          ? pieces.sublist(1).join('-').split('.')
          : const <String>[],
    );
  }

  @override
  int compareTo(_ParsedVersion other) {
    final width = core.length > other.core.length
        ? core.length
        : other.core.length;
    for (var index = 0; index < width; index += 1) {
      final left = index < core.length ? core[index] : 0;
      final right = index < other.core.length ? other.core[index] : 0;
      if (left != right) {
        return left.compareTo(right);
      }
    }
    return _comparePrerelease(other);
  }

  int _comparePrerelease(_ParsedVersion other) {
    if (prerelease.isEmpty && other.prerelease.isEmpty) {
      return 0;
    }
    if (prerelease.isEmpty) {
      return 1;
    }
    if (other.prerelease.isEmpty) {
      return -1;
    }
    final width = prerelease.length > other.prerelease.length
        ? prerelease.length
        : other.prerelease.length;
    for (var index = 0; index < width; index += 1) {
      if (index >= prerelease.length) {
        return -1;
      }
      if (index >= other.prerelease.length) {
        return 1;
      }
      final left = prerelease[index];
      final right = other.prerelease[index];
      if (left == right) {
        continue;
      }
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null) {
        return leftNumber.compareTo(rightNumber);
      }
      if (leftNumber != null) {
        return -1;
      }
      if (rightNumber != null) {
        return 1;
      }
      return left.compareTo(right);
    }
    return 0;
  }
}
