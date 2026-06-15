import 'package:flutter/material.dart';

/// 条目色块底/字色，按 id 稳定取色。
(Color, Color) avatarColors(String id) {
  const palette = <(Color, Color)>[
    (Color(0xFFFAECE7), Color(0xFF712B13)),
    (Color(0xFFE1F5EE), Color(0xFF085041)),
    (Color(0xFFFBE9E7), Color(0xFFB0341A)),
    (Color(0xFFE8EAF6), Color(0xFF283593)),
    (Color(0xFFE3F2E9), Color(0xFF1B5E20)),
    (Color(0xFFF3E5F5), Color(0xFF6A1B9A)),
  ];
  return palette[id.hashCode.abs() % palette.length];
}

/// 条目首字母方形头像，列表与详情共用（尺寸可调）。
class EntryAvatar extends StatelessWidget {
  const EntryAvatar({
    super.key,
    required this.id,
    required this.initial,
    this.size = 32,
  });

  final String id;
  final String initial;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = avatarColors(id);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        initial,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
