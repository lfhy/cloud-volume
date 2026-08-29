// TabNavHistory 纯逻辑契约:访问去重、回退跳过不可见项、历史耗尽语义。

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/state/tab_nav_history.dart';

void main() {
  test('连续重复访问不入栈,canGoBack 随历史长度变化', () {
    final history = TabNavHistory<int>();
    expect(history.canGoBack, isFalse);
    history.visit(1);
    history.visit(1); // 重复点击当前 tab。
    expect(history.entries, [1]);
    expect(history.canGoBack, isFalse);
    history.visit(2);
    expect(history.canGoBack, isTrue);
    expect(history.entries, [1, 2]);
  });

  test('back 移除当前项并返回上一个', () {
    final history = TabNavHistory<String>();
    history
      ..visit('a')
      ..visit('b')
      ..visit('c');
    expect(history.back((_) => true, current: 'c'), 'b');
    expect(history.entries, ['a', 'b']);
  });

  test('back 跳过不可见(已从底栏移除)的项并截断历史', () {
    final history = TabNavHistory<String>();
    history
      ..visit('a')
      ..visit('removed')
      ..visit('b');
    // b 回退时 'removed' 已不在底栏,应继续回退到 'a'。
    expect(history.back((item) => item != 'removed', current: 'b'), 'a');
    expect(history.entries, ['a']);
  });

  test('历史耗尽时 back 返回 null', () {
    final history = TabNavHistory<int>();
    history.visit(1);
    expect(history.back((_) => true, current: 1), isNull);
    expect(history.canGoBack, isFalse);
  });

  test('整条历史不可见(栈底被移出底栏)时 back 重置为当前项,不死锁', () {
    final history = TabNavHistory<String>();
    history
      ..visit('removed') // 冷启动项,后被用户从底栏移除。
      ..visit('removed2')
      ..visit('current');
    // 无任何可见项:保持当前页、历史重置为当前项,下一次返回即可退出。
    expect(history.back((_) => false, current: 'current'), isNull);
    expect(history.entries, ['current']);
    expect(history.canGoBack, isFalse);
    // 重置后可正常继续累积与回退。
    history.visit('next');
    expect(history.back((_) => true, current: 'next'), 'current');
  });

  test('reset 清空历史仅保留传入项', () {
    final history = TabNavHistory<int>();
    history
      ..visit(1)
      ..visit(2);
    history.reset(3);
    expect(history.entries, [3]);
    expect(history.canGoBack, isFalse);
  });
}
