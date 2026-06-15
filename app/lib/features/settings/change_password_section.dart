import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/strength_bar.dart';
import '../../services/password_gen.dart';
import '../../services/vault_service.dart';
import '../unlock/unlock_page.dart';
import 'settings_page.dart';

/// 修改主密码（T2.12）：当前密码验证 → 新密码强度门槛 → 改密后立即锁定并退回解锁页。
///
/// 当前密码是否正确由 [VaultSession.changePassword] 在 Rust 侧校验（错误映射为
/// [WrongPasswordException]）；新密码强度由 zxcvbn 评估，未达 [minScore] 不允许提交。
class ChangePasswordSection extends ConsumerStatefulWidget {
  const ChangePasswordSection({super.key});

  /// 新密码强度门槛：zxcvbn score（0–4）至少为 3（"强"）。
  static const minScore = 3;

  @override
  ConsumerState<ChangePasswordSection> createState() =>
      _ChangePasswordSectionState();
}

class _ChangePasswordSectionState extends ConsumerState<ChangePasswordSection> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  var _obscure = true;
  var _submitting = false;
  String? _error;
  PasswordStrength? _strength;

  @override
  void initState() {
    super.initState();
    _next.addListener(_evaluate);
  }

  @override
  void dispose() {
    _next.removeListener(_evaluate);
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _evaluate() {
    final value = _next.text;
    final service = ref.read(passwordGeneratorServiceProvider);
    setState(() {
      _strength = value.isEmpty ? null : service.evaluateStrength(value);
    });
  }

  /// 提交前的本地校验，返回错误文案或 null（通过）。
  String? _validate() {
    if (_current.text.isEmpty) return '请输入当前主密码';
    if (_next.text.isEmpty) return '请输入新主密码';
    if ((_strength?.score ?? 0) < ChangePasswordSection.minScore) {
      return '新主密码强度不足，请使用更复杂的密码';
    }
    if (_next.text == _current.text) return '新主密码不能与当前主密码相同';
    if (_confirm.text != _next.text) return '两次输入的新主密码不一致';
    return null;
  }

  Future<void> _submit() async {
    final localError = _validate();
    if (localError != null) {
      setState(() => _error = localError);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final notifier = ref.read(vaultProvider.notifier);
      await notifier.changePassword(_current.text, _next.text);
      // 验收：改密后立即锁定，要求用新密码重新解锁。
      await notifier.lock();
      if (mounted) context.go(UnlockPage.path);
    } on WrongPasswordException {
      setState(() => _error = '当前主密码不正确');
    } on VaultLockedException {
      setState(() => _error = '请先解锁保险库再修改主密码');
    } on VaultException catch (e) {
      setState(() => _error = '修改失败：${e.message}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SettingsCard(
      title: '主密码',
      children: [
        _field(controller: _current, hint: '当前主密码'),
        const SizedBox(height: 10),
        _field(controller: _next, hint: '新主密码'),
        if (_strength != null) ...[
          const SizedBox(height: 8),
          PasswordStrengthBar(strength: _strength!),
        ],
        const SizedBox(height: 10),
        _field(controller: _confirm, hint: '确认新主密码'),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: TextStyle(color: colorScheme.error, fontSize: 13),
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('修改主密码'),
          ),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      obscureText: _obscure,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.key_outlined),
        suffixIcon: IconButton(
          tooltip: _obscure ? '显示密码' : '隐藏密码',
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
