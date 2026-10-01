import 'package:flutter/material.dart';

import '../ble_protocol.dart';
import '../connect.dart';
import '../theme.dart';
import '../widget.dart';
import 'log_screen.dart';

/// 설정 화면.
/// 기기 연결 정보는 별도의 카드로 상단에 항상 표시하고, 그 아래로 설정 항목들을
/// 모아놓은 카드를 배치한다. 기기가 연결된 상태일 때만 설정 카드 안에
/// 로그 / 기기 연결 해제 / 진동 / 경고음 항목을 얇은 구분선으로 나눠 보여준다.
/// 진동과 경고음은 각각 토글로 켜고 끌 수 있고, 켜져 있을 때만 세기 슬라이더가 함께 보인다.
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
        final settings = connection.settings;
        final anyFeedbackOn =
            settings != null && (settings.soundEnabled || settings.vibrationEnabled);

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
                    const _FeedbackSetting(type: PreviewType.vibration),
                    _thinDivider,
                    const _FeedbackSetting(type: PreviewType.sound),
                  ],
                ),
              ),
              if (anyFeedbackOn) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '슬라이더를 놓으면 기기에서 바로 확인할 수 있어요',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

/// 진동 / 경고음 한 종류의 on-off 토글과, 켜져 있을 때만 아래에 함께 보이는 1~5단계 세기 슬라이더.
/// 값의 원본은 기기에서 읽어온 [DeviceConnection.settings]이고, 슬라이더를 놓거나 토글을 켜는 순간
/// 기기에 쓰면서 그 단계로 잠깐 울리거나 진동시켜 확인할 수 있게 한다.
class _FeedbackSetting extends StatefulWidget {
  const _FeedbackSetting({required this.type});

  final PreviewType type;

  @override
  State<_FeedbackSetting> createState() => _FeedbackSettingState();
}

class _FeedbackSettingState extends State<_FeedbackSetting> {
  final _connection = DeviceConnection.instance;

  /// 드래그 중인 단계. 손을 떼고 기기에 쓴 뒤에는 다시 기기 값을 따른다.
  int? _dragLevel;

  bool get _isVibration => widget.type == PreviewType.vibration;

  String get _title => _isVibration ? '진동' : '경고음';
  String get _caption => _isVibration ? '진동 세기' : '음량';
  IconData get _icon =>
      _isVibration ? Icons.vibration_rounded : Icons.volume_up_rounded;

  int _levelOf(DeviceSettings s) => _isVibration ? s.vibration : s.volume;
  bool _enabledOf(DeviceSettings s) =>
      _isVibration ? s.vibrationEnabled : s.soundEnabled;
  bool _otherEnabledOf(DeviceSettings s) =>
      _isVibration ? s.soundEnabled : s.vibrationEnabled;

  DeviceSettings _withLevel(DeviceSettings s, int level) =>
      _isVibration ? s.copyWith(vibration: level) : s.copyWith(volume: level);
  DeviceSettings _withEnabled(DeviceSettings s, bool enabled) => _isVibration
      ? s.copyWith(vibrationEnabled: enabled)
      : s.copyWith(soundEnabled: enabled);

  Future<void> _commitLevel(int level) async {
    final current = _connection.settings;
    if (current == null) return;
    await _connection.updateSettings(_withLevel(current, level));
    await _connection.previewSetting(widget.type, level);
    if (mounted) setState(() => _dragLevel = null);
  }

  /// 둘 다 꺼지면 졸음 경고를 전달할 수단이 없으므로 마지막 하나는 끄지 못하게 막는다.
  /// 펌웨어도 같은 쓰기를 거부하지만, 여기서 먼저 막아 이유를 알려준다.
  Future<void> _toggle(bool enabled) async {
    final current = _connection.settings;
    if (current == null) return;
    if (!enabled && !_otherEnabledOf(current)) {
      await showAppDialog(
        context: context,
        message: '진동과 경고음을 모두 끄면 졸음 경고를 받을 수 없어요.\n하나는 켜 두세요.',
        actions: [const AppDialogAction(label: '확인')],
      );
      return;
    }
    await _connection.updateSettings(_withEnabled(current, enabled));
    if (enabled) {
      await _connection.previewSetting(widget.type, _levelOf(current));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // 부모가 이 위젯을 const 로 만들어 두므로, 설정이 바뀔 때 다시 그리려면 직접 구독해야 한다.
    return ListenableBuilder(
      listenable: _connection,
      builder: (context, _) {
        final settings = _connection.settings;
        final enabled = settings != null && _enabledOf(settings);
        final level = _dragLevel ??
            (settings == null
                ? SettingLevel.defaultLevel
                : _levelOf(settings));

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
              child: Row(
                children: [
                  Icon(_icon, color: AppColors.textSecondary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_title, style: textTheme.bodyMedium),
                  ),
                  Switch(
                    value: enabled,
                    onChanged: settings == null ? null : _toggle,
                  ),
                ],
              ),
            ),
            if (enabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(34, 0, 20, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(_caption, style: textTheme.bodySmall),
                        const Spacer(),
                        Text(
                          '$level / ${SettingLevel.max}',
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                    Slider(
                      value: level.toDouble(),
                      min: SettingLevel.min.toDouble(),
                      max: SettingLevel.max.toDouble(),
                      divisions: SettingLevel.max - SettingLevel.min,
                      label: '$level',
                      onChanged: (v) => setState(() => _dragLevel = v.round()),
                      onChangeEnd: (v) => _commitLevel(v.round()),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
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
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

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
