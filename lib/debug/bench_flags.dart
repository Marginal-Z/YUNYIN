/// 流畅度测试用的对照开关（只由 mobile_benchmark.dart 在测试中打开，界面上没有入口）：
/// 逐项关掉一种绘制开销，看哪一项让帧超时。
abstract final class BenchFlags {
  /// 不画卡片的外阴影。
  static bool noShadow = false;

  /// 隐藏底部导航栏与迷你播放条（含玻璃背景模糊）。
  static bool noChrome = false;

  /// 页面转场不用快照，直接缩放页面。
  static bool noSnapshot = false;

  /// 页面转场用快照，但动画中不每 80 毫秒重拍。
  static bool noSnapshotRefresh = false;
}
