// MobileNavPreferences 契约:默认顺序、持久化往返、损坏/非法数据回退、
// 保存约束(2–5 项、可选池过滤、首页/设置至少保留一个)。

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/sidebar_item.dart';
import 'package:remote_storage/state/mobile_nav_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MobileNavPreferences.instance.resetForTest();
  });

  test('未加载/无存储时返回默认顺序(文件·账号·首页·任务·回收站)', () async {
    await MobileNavPreferences.instance.load();
    expect(MobileNavPreferences.instance.items, [
      SidebarItem.fileManager,
      SidebarItem.storage,
      SidebarItem.home,
      SidebarItem.transfers,
      SidebarItem.trash,
    ]);
  });

  test('save 后 load 往返保持顺序', () async {
    await MobileNavPreferences.instance.save([
      SidebarItem.home,
      SidebarItem.fileManager,
      SidebarItem.transfers,
    ]);
    MobileNavPreferences.instance.resetForTest();
    await MobileNavPreferences.instance.load();
    expect(MobileNavPreferences.instance.items, [
      SidebarItem.home,
      SidebarItem.fileManager,
      SidebarItem.transfers,
    ]);
  });

  test('损坏/未知/重复数据回退默认', () async {
    SharedPreferences.setMockInitialValues({
      kMobileBottomBarKey: '["home","home","bogus",123,,"settings"]',
    });
    await MobileNavPreferences.instance.load();
    // home+settings 合法但只剩 2 项,满足约束 → 保留解析结果。
    expect(MobileNavPreferences.instance.items, [
      SidebarItem.home,
      SidebarItem.settings,
    ]);

    // 完全非法数据 → 回退默认。
    SharedPreferences.setMockInitialValues({
      kMobileBottomBarKey: 'not-json-at-all',
    });
    MobileNavPreferences.instance.resetForTest();
    await MobileNavPreferences.instance.load();
    expect(
      MobileNavPreferences.instance.items,
      kMobileBottomBarDefault,
    );
  });

  test('解析结果不满足约束(无首页且无设置)时回退默认', () async {
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
      SidebarItem.home,
      SidebarItem.shares, // 池外(分享不在移动底栏可选池)。
      SidebarItem.fileSyncTasks, // 池外(移动端无同步)。
      SidebarItem.settings,
    ]);
    expect(MobileNavPreferences.instance.items, [
      SidebarItem.trash,
      SidebarItem.home,
      SidebarItem.settings,
    ]);
  });

  test('save 超过 5 项显式报错而非静默截断', () async {
    expect(
      () => MobileNavPreferences.instance.save(kMobileBottomBarPool),
      throwsArgumentError,
    );
    // 状态未被破坏性修改。
    expect(MobileNavPreferences.instance.items, kMobileBottomBarDefault);
  });

  test('save 拒绝少于 2 项或同移除首页+设置', () async {
    expect(
      () => MobileNavPreferences.instance.save([SidebarItem.home]),
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
    expect(
      MobileNavPreferences.instance.items,
      kMobileBottomBarDefault,
    );
  });
}
