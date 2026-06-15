import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/strength_bar.dart';
import '../../services/password_gen.dart';
import '../../services/vault_service.dart';
import '../shell/main_page.dart';
import 'vault_location.dart';

/// 解锁页（T2.6 真实化）：接通解锁/建库，错误抖动 + 连续 5 次后递增等待。
///
/// 库不存在时进入建库模式（主密码 + 确认 + zxcvbn 强度门槛），存在时为解锁模式。
/// 连续输错 [_lockoutThreshold] 次后禁用输入并显示 2ⁿ 秒递增倒计时（本机防暴力）。
class UnlockPage extends ConsumerStatefulWidget {
  const UnlockPage({super.key});

  static const path = '/unlock';

  /// 触发递增等待的连续错误次数阈值。
  static const _lockoutThreshold = 5;

  /// 新建库的强度门槛：zxcvbn score ≥ 3。
  static const _minScore = 3;

  @override
  ConsumerState<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends ConsumerState<UnlockPage>
    with SingleTickerProviderStateMixin {
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  late final AnimationController _shake;

  var _obscure = true;
  var _submitting = false;
  var _failCount = 0;
  var _lockoutRemaining = 0;
  var _create = false;
  String? _error;
  PasswordStrength? _strength;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _password.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _shake.dispose();
    _password.removeListener(_onPasswordChanged);
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _onPasswordChanged() {
    if (!_create) return;
    final value = _password.text;
    final service = ref.read(passwordGeneratorServiceProvider);
    setState(() {
      _strength = value.isEmpty ? null : service.evaluateStrength(value);
    });
  }

  void _startLockout() {
    // 第 5 次错误 → 2s，之后每次错误翻倍（2ⁿ），上限 5 分钟。
    final seconds = (1 << (_failCount - UnlockPage._lockoutThreshold + 1))
        .clamp(1, 300);
    setState(() => _lockoutRemaining = seconds);
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _lockoutRemaining--);
      if (_lockoutRemaining <= 0) {
        timer.cancel();
        _lockoutTimer = null;
      }
    });
  }

  bool get _locked => _lockoutRemaining > 0;

  void _shakeNow() => _shake.forward(from: 0);

  Future<void> _submit(VaultLocation location) async {
    if (_locked || _submitting) return;

    if (_password.text.isEmpty) {
      setState(() => _error = '请输入主密码');
      _shakeNow();
      return;
    }
    if (_create) {
      if ((_strength?.score ?? 0) < UnlockPage._minScore) {
        setState(() => _error = '主密码强度不足，请使用更复杂的密码');
        _shakeNow();
        return;
      }
      if (_confirm.text != _password.text) {
        setState(() => _error = '两次输入的主密码不一致');
        _shakeNow();
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final notifier = ref.read(vaultProvider.notifier);
      if (location.exists) {
        await notifier.unlock(location.path, _password.text);
      } else {
        await notifier.create(location.path, _password.text);
      }
      _failCount = 0;
      if (mounted) context.go(MainPage.path);
    } on WrongPasswordException {
      _failCount++;
      _shakeNow();
      setState(() => _error = '主密码不正确');
      if (_failCount >= UnlockPage._lockoutThreshold) _startLockout();
    } on VaultAlreadyExistsException {
      setState(() => _error = '该位置已存在保险库');
    } on VaultException catch (e) {
      setState(() => _error = '操作失败：${e.message}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final location = ref.watch(vaultLocationProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: location.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text(
                  '无法定位保险库：$e',
                  style: TextStyle(color: colorScheme.error),
                ),
                data: _buildCard,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(VaultLocation location) {
    _create = !location.exists;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fileName = location.path.split(RegExp(r'[\\/]')).last;

    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final dx = math.sin(_shake.value * math.pi * 4) * 8 * (1 - _shake.value);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _create ? Icons.add_moderator_outlined : Icons.lock_outline,
                    color: colorScheme.onPrimaryContainer,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'PwVault',
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _create ? '创建新保险库' : '保险库已锁定',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              _VaultRow(fileName: fileName, colorScheme: colorScheme),
              const SizedBox(height: 12),
              _passwordField(
                controller: _password,
                hint: '主密码',
                onSubmitted: _create ? null : (_) => _submit(location),
                trailingSubmit: !_create,
                location: location,
              ),
              if (_create) ...[
                if (_strength != null) ...[
                  const SizedBox(height: 8),
                  PasswordStrengthBar(strength: _strength!),
                ],
                const SizedBox(height: 12),
                _passwordField(
                  controller: _confirm,
                  hint: '确认主密码',
                  onSubmitted: (_) => _submit(location),
                  trailingSubmit: false,
                  location: location,
                ),
              ],
              const SizedBox(height: 12),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: colorScheme.error, fontSize: 13),
                )
              else
                Text(
                  _create ? '请牢记主密码，丢失后无法找回' : '连续输错 5 次将强制等待',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              if (_locked) ...[
                const SizedBox(height: 8),
                Text(
                  '请等待 $_lockoutRemaining 秒后重试',
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
                ),
              ],
              if (_create) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: (_submitting || _locked)
                      ? null
                      : () => _submit(location),
                  child: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('创建保险库'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String hint,
    required bool trailingSubmit,
    required VaultLocation location,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: _obscure,
      enabled: !_locked && !_submitting,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.key_outlined),
        suffixIcon: SizedBox(
          width: trailingSubmit ? 96 : 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: _obscure ? '显示密码' : '隐藏密码',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
              if (trailingSubmit)
                IconButton(
                  tooltip: '解锁',
                  onPressed: (_submitting || _locked)
                      ? null
                      : () => _submit(location),
                  icon: const Icon(Icons.arrow_forward),
                ),
            ],
          ),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _VaultRow extends StatelessWidget {
  const _VaultRow({required this.fileName, required this.colorScheme});

  final String fileName;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.storage_outlined,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
