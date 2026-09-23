// compactDisplayName 的回归：短名原样返回；长名保留头部、尾部与扩展名
// （中段省略）；预算不足时安全退化为纯头部截断（扩展名不保），不抛异常。

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/utils/display_name.dart';

void main() {
  test('short names pass through untouched', () {
    expect(compactDisplayName('a.jpg'), 'a.jpg');
    expect(compactDisplayName('photo.png', maxLength: 14), 'photo.png');
  });

  test('long names keep head, tail and extension', () {
    final result = compactDisplayName(
      'abcdefghij-filename.jpg',
      maxLength: 14,
    );
    // stem='abcdefghij-filename'；available=7 → head 4、tail 3('ame')。
    expect(result, 'abcd...ame.jpg');
    expect(result.startsWith('abcd'), isTrue);
    expect(result.endsWith('.jpg'), isTrue);
    expect(result.contains('...'), isTrue);
  });

  test('extension-less names keep head and tail', () {
    final result = compactDisplayName('abcdefghijklmnop', maxLength: 10);
    expect(result, 'abcd...nop');
  });

  test('tiny budget degrades to a plain head cut without crashing', () {
    final result = compactDisplayName('abcdefgh.png', maxLength: 8);
    // available = 8 - 4(.png) - 3 = 1 < 2 → 纯头部截断兜底（扩展名不保）。
    expect(result, 'abcde...');
  });

  test('extreme inputs pass through or degrade safely', () {
    // 空串、单字符、纯扩展名（dot==0 视为无扩展名）。
    expect(compactDisplayName(''), '');
    expect(compactDisplayName('a'), 'a');
    expect(compactDisplayName('.png'), '.png');
    // 超长扩展名（长度过半）按无扩展名处理：头尾保留。
    final long = compactDisplayName('ab.verylongextension', maxLength: 12);
    expect(long, startsWith('a'));
    expect(long, contains('...'));
  });
}
