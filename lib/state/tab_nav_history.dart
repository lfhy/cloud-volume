// 移动端 tab 访问历史:记录底栏/入口的访问顺序,让安卓系统返回键回退到
// 上一个页面而不是直接退出应用;历史耗尽时才允许退出。
// 纯逻辑类,便于单元测试;UI 集成见 main_layout_page.dart 的 PopScope。

/// 以栈方式维护的访问历史(含当前项)。
class TabNavHistory<T> {
  final List<T> _history = <T>[];

  /// 记录一次访问;连续重复访问(点击当前 tab)不入栈。
  void visit(T item) {
    if (_history.isNotEmpty && _history.last == item) return;
    _history.add(item);
  }

  /// 是否还有可回退的上一个页面。
  bool get canGoBack => _history.length > 1;

  /// 回退到上一个页面并从历史移除当前项;无可回退时返回 null。
  /// [visible] 过滤掉已不在底栏配置中的项(回退不应落在无按钮的页面)。
  /// 若整条历史都不可见(例如栈底项被用户从底栏移除),把历史重置为
  /// [current] 并返回 null——调用方保持当前页,下一次系统返回即可退出
  /// 应用,避免返回键被永久拦截的死锁。
  T? back(bool Function(T item) visible, {required T current}) {
    while (_history.length > 1) {
      _history.removeLast();
      final previous = _history.last;
      if (visible(previous)) return previous;
    }
    reset(current);
    return null;
  }

  /// 清空历史并仅保留 [item](配置重载等场景)。
  void reset(T item) {
    _history
      ..clear()
      ..add(item);
  }

  /// 测试/诊断用途。
  List<T> get entries => List<T>.unmodifiable(_history);
}
