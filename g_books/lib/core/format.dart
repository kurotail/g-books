/// 把 [Duration] 格式化成 `mm:ss`（分鐘補到兩位）。倒數顯示共用。
String formatMmSs(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
