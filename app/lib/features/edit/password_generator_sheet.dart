import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/password_gen.dart';

/// 打开生成器弹层，采纳时返回生成结果，取消返回 null。
Future<String?> showPasswordGeneratorDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PasswordGeneratorSheet(
            onAdopt: (pw) => Navigator.of(ctx).pop(pw),
          ),
        ),
      ),
    ),
  );
}

/// 内嵌密码生成器弹层（T2.10）：长度/字符集/短语模式 + 强度条，采纳后回填表单。
class PasswordGeneratorSheet extends ConsumerStatefulWidget {
  const PasswordGeneratorSheet({super.key, required this.onAdopt});

  /// 采纳生成结果。
  final ValueChanged<String> onAdopt;

  @override
  ConsumerState<PasswordGeneratorSheet> createState() =>
      _PasswordGeneratorSheetState();
}

class _PasswordGeneratorSheetState
    extends ConsumerState<PasswordGeneratorSheet> {
  static const _separators = <String, String>{
    '-': '连字符',
    ' ': '空格',
    '_': '下划线',
  };

  bool _passphrase = false;
  double _length = 20;
  double _words = 4;
  String _separator = '-';
  bool _uppercase = true;
  bool _lowercase = true;
  bool _numbers = true;
  bool _symbols = true;
  bool _excludeAmbiguous = false;

  String _result = '';
  String? _error;
  PasswordStrength? _strength;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  PasswordGenerationOptions get _options => PasswordGenerationOptions(
    length: _length.round(),
    uppercase: _uppercase,
    lowercase: _lowercase,
    numbers: _numbers,
    symbols: _symbols,
    excludeAmbiguous: _excludeAmbiguous,
  );

  Future<void> _generate() async {
    if (_generating) return;
    _generating = true;
    final service = ref.read(passwordGeneratorServiceProvider);
    try {
      final result = _passphrase
          ? await service.generatePassphrase(
              words: _words.round(),
              separator: _separator,
            )
          : await service.generatePassword(_options);
      if (!mounted) return;
      setState(() {
        _result = result;
        _error = null;
        _strength = service.evaluateStrength(result);
      });
    } on ArgumentError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message?.toString() ?? '生成参数无效';
        _result = '';
        _strength = null;
      });
    } finally {
      _generating = false;
    }
  }

  void _update(VoidCallback change) {
    setState(change);
    _generate();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('密码生成器', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('随机密码')),
            ButtonSegment(value: true, label: Text('助记短语')),
          ],
          selected: {_passphrase},
          onSelectionChanged: (s) => _update(() => _passphrase = s.first),
        ),
        const SizedBox(height: 12),
        _ResultBox(
          result: _result,
          error: _error,
          strength: _passphrase ? null : _strength,
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 12),
        if (_passphrase)
          ..._passphraseControls(context)
        else
          ..._passwordControls(context),
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新生成'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _result.isEmpty ? null : () => widget.onAdopt(_result),
              child: const Text('采纳'),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _passwordControls(BuildContext context) => [
    Row(
      children: [
        const Text('长度'),
        Expanded(
          child: Slider(
            value: _length,
            min: 8,
            max: 64,
            divisions: 56,
            label: '${_length.round()}',
            onChanged: (v) => _update(() => _length = v),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text('${_length.round()}', textAlign: TextAlign.end),
        ),
      ],
    ),
    Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        _toggle('大写', _uppercase, (v) => _uppercase = v),
        _toggle('小写', _lowercase, (v) => _lowercase = v),
        _toggle('数字', _numbers, (v) => _numbers = v),
        _toggle('符号', _symbols, (v) => _symbols = v),
        _toggle('排除易混', _excludeAmbiguous, (v) => _excludeAmbiguous = v),
      ],
    ),
  ];

  List<Widget> _passphraseControls(BuildContext context) => [
    Row(
      children: [
        const Text('词数'),
        Expanded(
          child: Slider(
            value: _words,
            min: 4,
            max: 6,
            divisions: 2,
            label: '${_words.round()}',
            onChanged: (v) => _update(() => _words = v),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text('${_words.round()}', textAlign: TextAlign.end),
        ),
      ],
    ),
    Row(
      children: [
        const Text('分隔符'),
        const SizedBox(width: 12),
        ..._separators.entries.map(
          (e) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(e.value),
              selected: _separator == e.key,
              onSelected: (_) => _update(() => _separator = e.key),
            ),
          ),
        ),
      ],
    ),
  ];

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: (v) => _update(() => onChanged(v)),
    );
  }
}

class _ResultBox extends StatelessWidget {
  const _ResultBox({
    required this.result,
    required this.error,
    required this.strength,
    required this.colorScheme,
  });

  final String result;
  final String? error;
  final PasswordStrength? strength;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            error ?? (result.isEmpty ? '生成中…' : result),
            style: TextStyle(
              fontFamily: 'monospace',
              color: error != null ? colorScheme.error : null,
            ),
          ),
          if (strength != null) ...[
            const SizedBox(height: 10),
            _StrengthBar(strength: strength!, colorScheme: colorScheme),
          ],
        ],
      ),
    );
  }
}

class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.strength, required this.colorScheme});

  final PasswordStrength strength;
  final ColorScheme colorScheme;

  static const _labels = ['很弱', '弱', '一般', '强', '很强'];

  @override
  Widget build(BuildContext context) {
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
