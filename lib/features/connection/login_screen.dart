import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/controller.dart';
import '../../core/lx_api.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _server;
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: widget.controller.server);
  }

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final success = await widget.controller.login(
      _server.text,
      _username.text,
      _password.text,
    );
    if (success && mounted) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 700;
            final showArtwork = constraints.maxHeight >= 480;
            final verticalPadding = compact ? 12.0 : 24.0;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: constraints.maxWidth < 360 ? 20 : 28,
                    vertical: verticalPadding,
                  ),
                  child: Form(
                    key: _form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: lxGreen,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(
                                Icons.graphic_eq_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'LX / MOBILE',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 16 : 36),
                        if (showArtwork) ...[
                          Center(
                            child: Container(
                              width: compact ? 72 : 138,
                              height: compact ? 72 : 138,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFE1F6ED),
                                border: Border.all(
                                  color: const Color(0xFFD2EFE2),
                                  width: compact ? 8 : 12,
                                ),
                              ),
                              child: Center(
                                child: Container(
                                  width: compact ? 52 : 86,
                                  height: compact ? 52 : 86,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: lxGreen,
                                  ),
                                  child: Icon(
                                    Icons.music_note_rounded,
                                    size: compact ? 30 : 46,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 8 : 20),
                          const Center(
                            child: Text(
                              '连接你的 LXServer',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (!compact) ...[
                            const SizedBox(height: 8),
                            const Center(
                              child: Text(
                                '用熟悉的账号，继续聆听。',
                                style: TextStyle(fontSize: 13, color: lxMuted),
                              ),
                            ),
                          ],
                          SizedBox(height: compact ? 16 : 32),
                        ],
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _server,
                              enabled: !c.loggingIn,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: '服务器地址',
                                hintText: 'https://music.example.com',
                                prefixIcon: Icon(Icons.dns_outlined),
                              ),
                              validator: (v) {
                                try {
                                  parseServer(v ?? '');
                                  return null;
                                } on ApiFailure {
                                  return '填写完整的 http:// 或 https:// 地址';
                                }
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _username,
                              enabled: !c.loggingIn,
                              autocorrect: false,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
                              decoration: const InputDecoration(
                                labelText: '账号',
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? '请输入账号'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _password,
                              enabled: !c.loggingIn,
                              obscureText: _obscure,
                              autocorrect: false,
                              enableSuggestions: false,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: '密码',
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: _obscure ? '显示密码' : '隐藏密码',
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                              validator: (v) =>
                                  v == null || v.isEmpty ? '请输入密码' : null,
                            ),
                            if (c.authError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Text(
                                  c.authError!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: c.loggingIn ? null : _submit,
                                child: c.loggingIn
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text('连接并登录'),
                                          SizedBox(width: 12),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
