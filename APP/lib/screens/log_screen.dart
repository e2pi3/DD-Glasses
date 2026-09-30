import 'package:flutter/material.dart';

import '../sensor_log.dart';
import '../theme.dart';

/// 기기가 500ms 마다 보내는 눈 추론 / IR 근접 / IMU 값을 실시간으로 보여주는 화면.
class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('로그')),
      body: ListenableBuilder(
        listenable: SensorLog.instance,
        builder: (context, _) {
          final entries = SensorLog.instance.entries;
          if (entries.isEmpty) {
            return Center(
              child: Text(
                '아직 받은 값이 없습니다',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.divider),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                dense: true,
                title: Text(entry.summary),
                trailing: Text(
                  _formatTime(entry.timestamp),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String _formatTime(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    final millis = (time.millisecond ~/ 100).toString();
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.$millis';
  }
}
