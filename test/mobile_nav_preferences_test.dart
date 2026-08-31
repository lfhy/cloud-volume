// MobileNavPreferences 契约:默认顺序、持久化往返、损坏/非法数据回退、
// 保存约束(2–5 项、可选池过滤、设置入口必须保留)。

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/sidebar_item.dart';
import 'package:remote_storage/state/mobile_nav_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MobileNavPreferences.instance.resetForTest();
  });

  test('未加载/无存储时返回默认顺序(文件·账号·任务·回收站·设置)', () async {
    await MobileNavPreferences.instance.load();
    expect(MobileNavPreferences.instance.items, [
      SidebarItem.fileManager,
      SidebarItem.storage,
      SidebarItem.transfers,
      SidebarItem.trash,
      SidebarItem.settings,
    ]);
  });

  test('save 后 load 往返保持顺序', () async {
    await MobileNavPreferences.instance.save([
      SidebarItem.settings,
      SidebarItem.fileManager,
      SidebarItem.transfers,
    ]);
    MobileNavPreferences.instance.resetForTest();
    await MobileNavPreferences.instance.load();
    expect(MobileNavPreferences.instance.items, [
      SidebarItem.settings,
      SidebarItem.fileManager,
      SidebarItem.transfers,
    ]);
  });

  test('旧首页数据迁移为设置,损坏数据回退默认', () async {
    SharedPreferences.setMockInitialValues({
      kMobileBottomBarKey:
          '["fileManager","storage","home","transfers","trash"]',
    });
    await MobileNavPreferences.instance.load();
    // 旧版本的 home tab 被迁移为设置,保持五项底栏可用。
    expect(MobileNavPreferences.instance.items, [
      SidebarItem.fileManager,
      SidebarItem.storage,
      SidebarItem.settings,
      SidebarItem.transfers,
      SidebarItem.trash,
    ]);

    // 完全非法数据 → 回退默认。
    SharedPreferences.setMockInitialValues({
      kMobileBottomBarKey: 'not-json-at-all',
    });
    MobileNavPreferences.instance.resetForTest();
    await MobileNavPreferences.instance.load();
    expect(MobileNavPreferences.instance.items, kMobileBottomBarDefault);
  });

  test('解析结果不满足约束(无设置)时回退默认', () async {
    SharedPreferences.setMockInitialValues({
      kMobileBottomBarKey: '["fileManager","transfers","trash"]',
    });
    await MobileNavPreferences.instance.load();
    expect(MobileNavPreferences.instance.items, kMobileBottomBarDefault);
  });

  test('save 过滤池外项并去重', () async {
    await MobileNavPreferences.instance.save([
      SidebarItem.trash,
      SidebarItem.trash,
      SidebarItem.shares, // 池外(分享不在移动底栏可选池)。
      SidebarItem.fileSyncTasks, // 池外(移动端无同步)。
      SidebarItem.settings,
    ]);
    expect(MobileNavPreferences.instance.items, [
      SidebarItem.trash,
      SidebarItem.settings,
    ]);
  });

  test('save 超过 5 项显式报错而非静默截断', () async {
    expect(
      () => MobileNavPreferences.instance.save([
        ...kMobileBottomBarPool,
        SidebarItem.shares,
      ]),
      throwsArgumentError,
    );
    // 状态未被破坏性修改。
    expect(MobileNavPreferences.instance.items, kMobileBottomBarDefault);
  });

  test('save 拒绝少于 2 项或移除设置', () async {
    expect(
      () => MobileNavPreferences.instance.save([SidebarItem.fileManager]),
      throwsArgumentError,
    );
    expect(
      () => MobileNavPreferences.instance.save([
        SidebarItem.fileManager,
        SidebarItem.transfers,
      ]),
      throwsArgumentError,
    );
    // 状态未被破坏性修改。
    expect(MobileNavPreferences.instance.items, kMobileBottomBarDefault);
  });
}
