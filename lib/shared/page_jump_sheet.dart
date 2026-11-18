import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import 'app_modal.dart';

Future<int?> showPageJump(
  BuildContext context, {
  required int currentPage,
  required int maxPage,
  bool totalKnown = true,
}) => showAppSheet<int>(
  context: context,
  builder: (_) => _PageJump(
    currentPage: currentPage,
    maxPage: maxPage,
    totalKnown: totalKnown,
  ),
);

class _PageJump extends StatefulWidget {
  const _PageJump({
    required this.currentPage,
    required this.maxPage,
    required this.totalKnown,
  });
  final int currentPage, maxPage;
  final bool totalKnown;
  @override
  State<_PageJump> createState() => _PageJumpState();
}

class _PageJumpState extends State<_PageJump> {
  late final TextEditingController _input = TextEditingController(
    text: '${widget.currentPage + 1}',
  );
  late final FixedExtentScrollController _wheel = FixedExtentScrollController(
    initialItem: widget.currentPage,
  );
  final _focus = FocusNode();
  late int? _value = widget.currentPage + 1;
  bool _typing = false;
  @override
  void dispose() {
    _input.dispose();
    _wheel.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _confirm() {
    final value = _value;
    if (value != null && value >= 1 && value <= widget.maxPage) {
      Navigator.pop(context, value - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final panelHeight = (height * .25).clamp(100.0, 180.0);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '跳转页码',
            subtitle:
                '当前第 ${widget.currentPage + 1} 页，${widget.totalKnown ? '共' : '已加载'} ${widget.maxPage} 页',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (final (label, typing) in [('输入页码', true), ('滚动选择', false)])
                  Padding(
                    padding: const EdgeInsets.only(right: 22),
                    child: InkWell(
                      onTap: () {
                        if (!typing) _focus.unfocus();
                        setState(() {
                          _typing = typing;
                          _value ??= widget.currentPage + 1;
                          _input.text = '$_value';
                        });
                        if (typing) {
                          _focus.requestFocus();
                        } else {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && _wheel.hasClients) {
                              _wheel.jumpToItem(_value! - 1);
                            }
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: _typing == typing
                                  ? lxGreen
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            color: _typing == typing ? lxGreen : lxMuted,
                            fontWeight: _typing == typing
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_typing)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: TextField(
                key: const ValueKey('page-jump-input'),
                style: modalInputTextStyle,
                controller: _input,
                focusNode: _focus,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.go,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                decoration: InputDecoration(
                  suffixText: '页',
                  hintText: '1–${widget.maxPage}',
                  errorText: _value == null
                      ? '请输入 1 至 ${widget.maxPage} 的整数'
                      : null,
                ),
                onChanged: (text) => setState(() {
                  final value = int.tryParse(text);
                  _value =
                      value != null && value >= 1 && value <= widget.maxPage
                      ? value
                      : null;
                }),
                onSubmitted: (_) => _confirm(),
              ),
            )
          else
            SizedBox(
              height: keyboard > 0 ? 100 : panelHeight,
              child: CupertinoPicker.builder(
                key: const ValueKey('page-jump-wheel'),
                scrollController: _wheel,
                itemExtent: MediaQuery.textScalerOf(context)
                    .scale(21)
                    .clamp(36, 80)
                    .toDouble(),
                childCount: widget.maxPage,
                diameterRatio: 1.5,
                selectionOverlay: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: const Color(0x1808B884),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onSelectedItemChanged: (index) => setState(() {
                  _value = index + 1;
                  _input.text = '$_value';
                }),
                itemBuilder: (_, index) => Center(
                  child: Text(
                    '${index + 1} 页',
                    style: TextStyle(
                      fontSize: 21,
                      color: _value == index + 1 ? lxGreen : lxMuted,
                      fontWeight: _value == index + 1
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _value == null ? null : _confirm,
                child: Text(_value == null ? '跳转' : '跳转至第 $_value 页'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
