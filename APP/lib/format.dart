/// 한 자리 수를 두 자리로 맞춘다 (3 -> 03).
String two(int n) => n.toString().padLeft(2, '0');

/// 시계처럼 `HH:MM:SS`로 표시한다. 24시간을 넘어도 시간 자리가 그대로 늘어난다.
String formatHms(Duration d) {
  final total = d.isNegative ? Duration.zero : d;
  return '${two(total.inHours)}:${two(total.inMinutes.remainder(60))}:'
      '${two(total.inSeconds.remainder(60))}';
}

/// `1시간 5분 12초`처럼 0인 단위는 빼고 읽기 좋게 표시한다. 전부 0이면 `0초`.
String formatKorean(Duration d) {
  final total = d.isNegative ? Duration.zero : d;
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60);
  final seconds = total.inSeconds.remainder(60);
  final parts = [
    if (hours > 0) '$hours시간',
    if (minutes > 0) '$minutes분',
    if (seconds > 0) '$seconds초',
  ];
  return parts.isEmpty ? '0초' : parts.join(' ');
}
