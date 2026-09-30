import 'package:flutter/material.dart';

import '../ble_protocol.dart';
import '../connect.dart';
import '../theme.dart';
import '../widget.dart';
import 'log_screen.dart';

/// 설정 화면.
/// 기기 연결 정보는 별도의 카드로 상단에 항상 표시하고, 그 아래로 설정 항목들을
/// 모아놓은 카드를 배치한다. 기기가 연결된 상태일 때만 설정 카드 안에
/// 로그 / 기기 연결 해제 / 피드백 강도 조절 / 경고음 음량 설정 항목을 얇은 구분선으로 나눠 보여준다.
class SettingScreen extends StatelessWidget {
  const SettingScreen({super.key});

  static const _thinDivider = Divider(
    height: 1,
    thickness: 1,
    indent: 20,
    endIndent: 20,
    color: AppColors.divider,
  );

  @override
  Widget build(BuildContext context) {
    final connection = DeviceConnection.instance;

    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(child: _DeviceInfoTile(connection: connection)),
            if (connection.isConnected) ...[
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  children: [
                    _SettingTile(
                      icon: Icons.list_alt_rounded,
                      title: '로그',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LogScreen()),
                      ),
                    ),
                    _thinDivider,
                    _SettingTile(
                      icon: Icons.bluetooth_disabled_rounded,
                      title: '기기 연결 해제',
                      onTap: () => showAppDialog(
                        context: context,
                        message: '연결을 해제하시겠습니까?',
                        actions: [
                          const AppDialogAction(label: '닫기'),
                          AppDialogAction(
                            label: '해제',
                            isDestructive: true,
                            onPressed: connection.disconnect,
                          ),
                        ],
                      ),
                    ),
                    _thinDivider,
                    _SettingTile(
                      icon: Icons.tune_rounded,
                      title: '피드백 강도 조절',
                      value: connection.settings?.vibration,
                      onTap: () => _showLevelSheet(
                        context,
                        title: '진동 세기',
                        icon: Icons.vibration_rounded,
                        previewType: PreviewType.vibration,
                        read: (s) => s.vibration,
                        write: (s, v) => s.copyWith(vibration: v),
                      ),
                    ),
                    _thinDivider,
                    _SettingTile(
                      icon: Icons.volume_up_rounded,
                      title: '경고음 음량 설정',
                      value: connection.settings?.volume,
                      onTap: () => _showLevelSheet(
                        context,
                        title: '경고음 음량',
                        icon: Icons.volume_up_rounded,
                        previewType: PreviewType.sound,
                        read: (s) => s.volume,
                        write: (s, v) => s.copyWith(volume: v),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 1~5단계 슬라이더 시트를 띄운다. 값은 기기에서 읽어온 [DeviceConnection.settings]가 원본이고,
/// 슬라이더를 놓는 순간 기기에 쓰고 그 단계로 잠깐 울리거나 진동시켜 확인할 수 있게 한다.
void _showLevelSheet(
  BuildContext context, {
  required String title,
  required IconData icon,
  required PreviewType previewType,
  required int Function(DeviceSettings) read,
  required DeviceSettings Function(DeviceSettings, int) write,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _LevelSheet(
      title: title,
      icon: icon,
      previewType: previewType,
      read: read,
      write: write,
    ),
  );
}

class _LevelSheet extends StatefulWidget {
  const _LevelSheet({
    required this.title,
    required this.icon,
    required this.previewType,
    required this.read,
    required this.write,
  });

  final String title;
  final IconData icon;
  final PreviewType previewType;
  final int Function(DeviceSettings) read;
  final DeviceSettings Function(DeviceSettings, int) write;

  @override
  State<_LevelSheet> createState() => _LevelSheetState();
}

class _LevelSheetState extends State<_LevelSheet> {
  final _connection = DeviceConnection.instance;
  int? _dragLevel;

  int get _level =>
      _dragLevel ??
      (_connection.settings == null
          ? SettingLevel.defaultLevel
          : widget.read(_connection.settings!));

  Future<void> _commit(int level) async {
    final current = _connection.settings;
    if (current == null) return;
    await _connection.updateSettings(widget.write(current, level));
    await _connection.previewSetting(widget.previewType, level);
    if (mounted) setState(() => _dragLevel = null);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final level = _level;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(widget.icon, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(child: Text(widget.title, style: textTheme.titleMedium)),
                Text('$level / ${SettingLevel.max}', style: textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Slider(
              value: level.toDouble(),
              min: SettingLevel.min.toDouble(),
              max: SettingLevel.max.toDouble(),
              divisions: SettingLevel.max - SettingLevel.min,
              label: '$level',
              onChanged: _connection.settings == null
                  ? null
                  : (v) => setState(() => _dragLevel = v.round()),
              onChangeEnd: (v) => _commit(v.round()),
            ),
            const SizedBox(height: 4),
            Text(
              '슬라이더를 놓으면 기기에서 바로 확인할 수 있어요',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceInfoTile extends StatelessWidget {
  const _DeviceInfoTile({required this.connection});

  final DeviceConnection connection;

  static const double _height = 112;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final connected = connection.isConnected;

    return SizedBox(
      height: _height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Icon(
              connected
                  ? Icons.bluetooth_connected_rounded
                  : Icons.bluetooth_rounded,
              color: connected ? colorScheme.primary : AppColors.textSecondary,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    connected ? '연결된 기기' : '연결된 기기 없음',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (connected) ...[
                    const SizedBox(height: 4),
                    Text(
                      connection.deviceId ?? '',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  /// 현재 설정 단계. 있으면 오른쪽에 `n/5`로 표시한다.
  final int? value;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.bodyMedium),
            ),
            if (value != null) ...[
              Text(
                '$value/${SettingLevel.max}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 4),
            ],
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
