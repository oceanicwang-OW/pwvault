import 'package:flutter/material.dart';

import '../services/password_gen.dart';

/// 密码强度条：5 档配色 + 文案，供生成器/改密/建库等处复用。
class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({super.key, required this.strength});

  final PasswordStrength strength;

  static const _labels = ['很弱', '弱', '一般', '强', '很强'];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final score = strength.score.clamp(0, 4);
    final color = switch (score) {
      0 || 1 => const Color(0xFFD64545),
      2 => const Color(0xFFE08A1E),
      3 => const Color(0xFF3DA35D),
      _ => const Color(0xFF1B873F),
    };
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (score + 1) / 5,
              minHeight: 6,
              color: color,
              backgroundColor: colorScheme.outlineVariant,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(_labels[score], style: TextStyle(color: color)),
      ],
    );
  }
}
