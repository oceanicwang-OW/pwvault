import 'dart:async';

import 'package:flutter/material.dart';

import 'field_row.dart';

/// 掩码固定渲染的圆点数，不反映真实密码长度（PDR 7.5）。
const _maskDotCount = 8;

/// 密码行状态机（T2.9 / PDR 7.5）：
///
/// ```
/// [掩码 ••••••••] ──点击👁──▶ [明文显示, 10s 倒计时]
///       ▲                              │
///       └─ 再次👁 / 倒计时归零 / 切后台 / 锁定 ─┘
/// ```
///
/// 明文走"单条目按需解密"（[revealPassword] 对照 `entry_reveal_password`），
/// 回隐时把 Dart 侧明文引用置空。
class PasswordFieldRow extends StatefulWidget {
  const PasswordFieldRow({
    super.key,
    required this.label,
    required this.revealPassword,
    required this.onCopy,
    this.revealTimeout = const Duration(seconds: 10),
  });

  final String label;
  final Future<String> Function() revealPassword;
  final Future<void> Function(String password) onCopy;
  final Duration revealTimeout;

  @override
  State<PasswordFieldRow> createState() => _PasswordFieldRowState();
}

class _PasswordFieldRowState extends State<PasswordFieldRow>
    with WidgetsBindingObserver {
  String? _plain;
  int _remaining = 0;
  Timer? _countdown;
  bool _revealing = false;

  bool get _revealed => _plain != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _plain = null; // 锁定/销毁路径：明文引用置空
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _revealed) {
      _hide(); // 切后台立即回隐
    }
  }

  Future<void> _toggle() async {
    if (_revealed) {
      _hide();
      return;
    }
    if (_revealing) return;
    _revealing = true;
    try {
      final plain = await widget.revealPassword();
      if (!mounted) return;
      setState(() {
        _plain = plain;
        _remaining = widget.revealTimeout.inSeconds;
      });
      _startCountdown();
    } finally {
      _revealing = false;
    }
  }

  void _startCountdown() {
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 1) {
        _hide(); // 倒计时归零回隐
      } else {
        setState(() => _remaining -= 1);
      }
    });
  }

  void _hide() {
    _countdown?.cancel();
    _countdown = null;
    setState(() {
      _plain = null;
      _remaining = 0;
    });
    assert(_plain == null, '回隐后明文引用必须为空');
  }

  Future<void> _copy() async {
    // 掩码态复制时按需取一次明文，不长期持有。
    final plain = _plain ?? await widget.revealPassword();
    await widget.onCopy(plain);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Widget value = _revealed
        ? Row(
            children: [
              Flexible(
                child: Text(
                  _plain!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(width: 8),
              _CountdownChip(seconds: _remaining, colorScheme: colorScheme),
            ],
          )
        : Text(
            '•' * _maskDotCount,
            style: const TextStyle(letterSpacing: 2, fontFamily: 'monospace'),
          );

    return FieldRow(
      label: widget.label,
      highlighted: true,
      value: value,
      actions: [
        IconButton(
          tooltip: _revealed ? '隐藏密码' : '显示密码',
          onPressed: _toggle,
          icon: Icon(
            _revealed
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 18,
          ),
        ),
        IconButton(
          tooltip: '复制密码',
          onPressed: _copy,
          icon: const Icon(Icons.copy_outlined, size: 18),
        ),
      ],
    );
  }
}

class _CountdownChip extends StatelessWidget {
  const _CountdownChip({required this.seconds, required this.colorScheme});

  final int seconds;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${seconds}s',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
