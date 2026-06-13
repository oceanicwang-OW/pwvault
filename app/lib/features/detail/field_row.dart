import 'package:flutter/material.dart';

/// 详情面板通用字段行（T2.9）：标签区 / 值区 / 操作区。
///
/// 值区由调用方传入任意 widget（纯文本、链接文本、标签 chip、密码行等），
/// 操作区是一组尾部图标按钮。[highlighted] 给敏感字段（如密码行）加底色，
/// [isLast] 去掉底部分隔线。
class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.label,
    required this.value,
    this.actions = const <Widget>[],
    this.highlighted = false,
    this.isLast = false,
  });

  final String label;
  final Widget value;
  final List<Widget> actions;
  final bool highlighted;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted ? colorScheme.surfaceContainerHighest : null,
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(child: value),
            ...actions,
          ],
        ),
      ),
    );
  }
}
