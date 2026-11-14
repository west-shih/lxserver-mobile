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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
              child: Form(
                key: _form,
                child: Column(
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
                    const SizedBox(height: 46),
                    Center(
                      child: Container(
                        width: 138,
                        height: 138,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFE1F6ED),
                          border: Border.all(
                            color: const Color(0xFFD2EFE2),
                            width: 12,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 86,
                            height: 86,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: lxGreen,
                            ),
                            child: const Icon(
                              Icons.music_note_rounded,
                              size: 46,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      '音乐，回到你身边。',
                      style: TextStyle(
                        fontSize: 29,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '连接你的 LXServer\n用熟悉的账号，开启下一首。',
                      style: TextStyle(
                        color: lxMuted,
                        fontSize: 15,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 28),
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
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? '请输入账号' : null,
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
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? '显示密码' : '隐藏密码',
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      validator: (v) => v == null || v.isEmpty ? '请输入密码' : null,
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
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('连接并登录'),
                                  SizedBox(width: 12),
                                  Icon(Icons.arrow_forward_rounded, size: 20),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Center(
                      child: Text(
                        '账号由服务管理员创建 · 无需注册',
                        style: TextStyle(color: lxMuted, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Center(
                      child: Text(
                        'LXServer 第三方客户端',
                        style: TextStyle(
                          color: lxMuted,
                          fontSize: 11,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
