import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/vault_service.dart';
import 'password_generator_sheet.dart';
import 'url_normalizer.dart';

/// 可选标签集合（暂为固定集；自定义标签留待后续）。
const kTagOptions = <String>['工作', '个人', '金融', '购物', '社交'];

/// 打开新建/编辑条目对话框；保存写入真实库（`VaultService.upsert`），列表即时刷新。
Future<void> showEntryEditDialog(BuildContext context, {EntryMeta? initial}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: EntryEditForm(
          initial: initial,
          onSubmit: (draft) async {
            await ProviderScope.containerOf(
              ctx,
            ).read(vaultProvider.notifier).upsert(draft);
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
          onCancel: () => Navigator.of(ctx).pop(),
        ),
      ),
    ),
  );
}

/// 条目编辑表单（T2.10）：标题必填、标签多选、URL 规范化、内嵌生成器、脏数据二次确认。
class EntryEditForm extends ConsumerStatefulWidget {
  const EntryEditForm({
    super.key,
    this.initial,
    required this.onSubmit,
    required this.onCancel,
  });

  final EntryMeta? initial;
  final Future<void> Function(EntryDraft draft) onSubmit;
  final VoidCallback onCancel;

  @override
  ConsumerState<EntryEditForm> createState() => _EntryEditFormState();
}

class _EntryEditFormState extends ConsumerState<EntryEditForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _url;
  late final TextEditingController _notes;
  late final Set<String> _tags;
  late bool _favorite;

  // 初始快照，用于脏数据判断。
  late final String _title0;
  late final String _username0;
  late final String _url0;
  late final Set<String> _tags0;
  late final bool _favorite0;

  bool _submitting = false;
  String? _submitError;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _title = TextEditingController(text: e?.title ?? '');
    _username = TextEditingController(text: e?.username ?? '');
    _password = TextEditingController();
    _url = TextEditingController(text: e?.url ?? '');
    _notes = TextEditingController();
    _tags = {...?e?.tags};
    _favorite = e?.favorite ?? false;

    _title0 = _title.text;
    _username0 = _username.text;
    _url0 = _url.text;
    _tags0 = {..._tags};
    _favorite0 = _favorite;
  }

  @override
  void dispose() {
    _title.dispose();
    _username.dispose();
    _password.dispose();
    _url.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _title.text != _title0 ||
      _username.text != _username0 ||
      _url.text != _url0 ||
      _favorite != _favorite0 ||
      _password.text.isNotEmpty ||
      _notes.text.isNotEmpty ||
      !_setEquals(_tags, _tags0);

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  Future<void> _attemptCancel() async {
    if (!_dirty) {
      widget.onCancel();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃未保存的更改？'),
        content: const Text('表单有未保存的内容，关闭后将丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (discard ?? false) widget.onCancel();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final draft = EntryDraft(
      id: widget.initial?.id,
      title: _title.text.trim(),
      username: _username.text.trim(),
      password: _password.text,
      url: normalizeUrl(_url.text),
      notes: _notes.text,
      tags: _tags.toList(),
      favorite: _favorite,
    );
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await widget.onSubmit(draft);
    } on VaultException catch (e) {
      if (mounted) setState(() => _submitError = '保存失败：${e.message}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openGenerator() async {
    final pw = await showPasswordGeneratorDialog(context);
    if (pw != null && mounted) {
      setState(() => _password.text = pw);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEdit ? '编辑条目' : '新建条目',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _title,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '标题 *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '标题不能为空' : null,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _username,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      decoration: InputDecoration(
                        labelText: '密码',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: '生成密码',
                          icon: const Icon(Icons.casino_outlined),
                          onPressed: _openGenerator,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _url,
                      decoration: const InputDecoration(
                        labelText: '网址',
                        border: OutlineInputBorder(),
                        hintText: 'example.com',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '标签',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final tag in kTagOptions)
                          FilterChip(
                            label: Text(tag),
                            selected: _tags.contains(tag),
                            onSelected: (sel) => setState(() {
                              sel ? _tags.add(tag) : _tags.remove(tag);
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('设为常用'),
                      value: _favorite,
                      onChanged: (v) => setState(() => _favorite = v),
                    ),
                  ],
                ),
              ),
            ),
            if (_submitError != null) ...[
              const SizedBox(height: 12),
              Text(
                _submitError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _submitting ? null : _attemptCancel,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
