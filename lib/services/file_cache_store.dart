// File cache store persists local cached-file metadata and cache paths in SQLite.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:remote_storage/models/cached_file_record.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 缓存统计信息。
class CacheStats {
  const CacheStats({required this.count, required this.totalBytes});

  final int count;
  final int totalBytes;

  String get formattedSize {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class FileCacheStore {
  FileCacheStore._();

  static final FileCacheStore instance = FileCacheStore._();

  static const _dbName = 'remote_storage_cache.db';
  static const _tableName = 'cached_files';
  static const _cacheDirName = 'files';

  Database? _database;
  Directory? _cacheRoot;
  String? _cacheRootPath;

  Future<String?> findUsableCachePath(
    String cacheDirectory,
    String bucket,
    ObjectInfo remoteObject,
  ) async {
    final root = await _cacheDirectory(cacheDirectory);
    final db = await _openDatabase();
    final rows = await db.query(
      _tableName,
      where: 'bucket = ? AND object_key = ?',
      whereArgs: <Object?>[bucket, remoteObject.key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final record = CachedFileRecord.fromJson(rows.first);
    final file = File(record.localPath);
    final fileExists = await file.exists();
    final fileSize = fileExists ? await file.length() : -1;
    if (!_isInsideRoot(root.path, record.localPath) ||
        !fileExists ||
        !_matchesRemoteObject(record, remoteObject) ||
        fileSize != remoteObject.size) {
      await removeCacheRecord(
        bucket: bucket,
        objectKey: remoteObject.key,
        localPath: record.localPath,
        deleteFile: true,
      );
      return null;
    }
    return record.localPath;
  }

  Future<String> cachePathFor(
    String cacheDirectory,
    String bucket,
    String objectKey,
  ) async {
    final root = await _cacheDirectory(cacheDirectory);
    final segments = <String>[
      root.path,
      _safeSegment(bucket),
      ...objectKey
          .split('/')
          .where((segment) => segment.isNotEmpty)
          .map(_safeSegment),
    ];
    final fullPath = path.joinAll(segments);
    await Directory(path.dirname(fullPath)).create(recursive: true);
    return fullPath;
  }

  Future<void> upsertCacheRecord({
    required String bucket,
    required ObjectInfo object,
    required String localPath,
  }) async {
    final db = await _openDatabase();
    await db.insert(
      _tableName,
      CachedFileRecord(
        bucket: bucket,
        objectKey: object.key,
        localPath: localPath,
        fileSize: object.size,
        lastModified: object.lastModified,
        updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      ).toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeCacheRecord({
    required String bucket,
    required String objectKey,
    String? localPath,
    bool deleteFile = false,
  }) async {
    final db = await _openDatabase();
    await db.delete(
      _tableName,
      where: 'bucket = ? AND object_key = ?',
      whereArgs: <Object?>[bucket, objectKey],
    );
    if (deleteFile && localPath != null) {
      await _deleteFileIfExists(localPath);
    }
  }

  Future<void> removeCachePrefix({
    required String bucket,
    required String objectKeyPrefix,
    bool deleteFiles = false,
  }) async {
    final db = await _openDatabase();
    final rows = await db.query(
      _tableName,
      columns: const <String>['local_path'],
      where: 'bucket = ? AND object_key LIKE ?',
      whereArgs: <Object?>[bucket, '$objectKeyPrefix%'],
    );
    await db.delete(
      _tableName,
      where: 'bucket = ? AND object_key LIKE ?',
      whereArgs: <Object?>[bucket, '$objectKeyPrefix%'],
    );
    if (!deleteFiles) {
      return;
    }
    for (final row in rows) {
      final localPath = (row['local_path'] ?? '').toString();
      if (localPath.isNotEmpty) {
        await _deleteFileIfExists(localPath);
      }
    }
  }

  Future<void> deleteFileIfExists(String localPath) async {
    await _deleteFileIfExists(localPath);
  }

  /// 返回缓存统计：实际存在于磁盘上的文件数量和总字节数。
  /// 会同时清理数据库中已不存在的文件记录。
  Future<CacheStats> getCacheStats() async {
    final db = await _openDatabase();
    final rows = await db.query(_tableName);
    int count = 0;
    int totalBytes = 0;
    final staleKeys = <Map<String, String>>[];

    for (final row in rows) {
      final localPath = (row['local_path'] ?? '').toString();
      final bucket = (row['bucket'] ?? '').toString();
      final objectKey = (row['object_key'] ?? '').toString();

      final file = File(localPath);
      final exists = await file.exists();
      if (!exists) {
        staleKeys.add({'bucket': bucket, 'object_key': objectKey});
        continue;
      }
      final actualSize = await file.length();
      count++;
      totalBytes += actualSize;
    }

    // 清理数据库中已不存在对应文件的脏记录。
    for (final key in staleKeys) {
      await db.delete(
        _tableName,
        where: 'bucket = ? AND object_key = ?',
        whereArgs: <Object?>[key['bucket'], key['object_key']],
      );
    }

    return CacheStats(count: count, totalBytes: totalBytes);
  }

  /// 清除所有缓存记录并删除对应的本地文件。返回实际删除的文件数量。
  Future<int> clearAllCache() async {
    final db = await _openDatabase();
    final rows = await db.query(_tableName, columns: const <String>['local_path']);
    int deletedCount = 0;
    for (final row in rows) {
      final localPath = (row['local_path'] ?? '').toString();
      if (localPath.isNotEmpty) {
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
          deletedCount++;
        }
      }
    }
    await db.delete(_tableName);
    // 清理残留的缓存目录结构（可能由于记录丢失而残留的空目录）。
    await _cleanupEmptyCacheDirs();
    return deletedCount;
  }

  /// 递归清理缓存根目录下的空子目录。
  Future<void> _cleanupEmptyCacheDirs() async {
    if (_cacheRoot == null || _cacheRootPath == null) return;
    final root = _cacheRoot!;
    if (!await root.exists()) return;
    final entities = await root.list(recursive: false).toList();
    for (final entity in entities) {
      if (entity is Directory && await entity.exists()) {
        try {
          await _removeEmptyDirsRecursive(entity);
        } on FileSystemException {
          // 忽略删除失败。
        }
      }
    }
  }

  Future<void> _removeEmptyDirsRecursive(Directory dir) async {
    if (!await dir.exists()) return;
    final entities = await dir.list(recursive: false).toList();
    for (final entity in entities) {
      if (entity is Directory) {
        await _removeEmptyDirsRecursive(entity);
      }
    }
    // 目录为空则删除。
    final remaining = await dir.list().toList();
    if (remaining.isEmpty) {
      await dir.delete();
    }
  }

  /// 返回缓存根目录路径。
  Future<String> getCacheDirectoryPath() async {
    if (_cacheRootPath != null) return _cacheRootPath!;
    return '';
  }

  Future<Database> _openDatabase() async {
    if (_database != null) {
      return _database!;
    }
    final supportDir = await getApplicationSupportDirectory();
    await supportDir.create(recursive: true);
    final dbPath = path.join(supportDir.path, _dbName);
    _database = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_tableName (
              bucket TEXT NOT NULL,
              object_key TEXT NOT NULL,
              local_path TEXT NOT NULL,
              file_size INTEGER NOT NULL,
              last_modified TEXT NOT NULL,
              updated_at_epoch_ms INTEGER NOT NULL,
              PRIMARY KEY (bucket, object_key)
            )
          ''');
        },
      ),
    );
    return _database!;
  }

  Future<Directory> _cacheDirectory(String cacheDirectory) async {
    final trimmedPath = cacheDirectory.trim();
    if (trimmedPath.isEmpty) {
      throw StateError('缓存目录未配置。');
    }
    final targetPath = path.join(trimmedPath, _cacheDirName);
    if (_cacheRoot != null && _cacheRootPath == targetPath) {
      return _cacheRoot!;
    }
    final cacheDir = Directory(targetPath);
    await cacheDir.create(recursive: true);
    _cacheRoot = cacheDir;
    _cacheRootPath = targetPath;
    return cacheDir;
  }

  bool _matchesRemoteObject(CachedFileRecord record, ObjectInfo remoteObject) {
    final sameSize = record.fileSize == remoteObject.size;
    final sameTimestamp =
        remoteObject.lastModified.isEmpty ||
        record.lastModified == remoteObject.lastModified;
    return sameSize && sameTimestamp;
  }

  String _safeSegment(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '_';
    }
    return trimmed
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll('..', '__');
  }

  Future<void> _deleteFileIfExists(String localPath) async {
    final file = File(localPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  bool _isInsideRoot(String rootPath, String localPath) {
    final normalizedRoot = path.normalize(rootPath);
    final normalizedLocal = path.normalize(localPath);
    return path.equals(normalizedRoot, normalizedLocal) ||
        path.isWithin(normalizedRoot, normalizedLocal);
  }
}
