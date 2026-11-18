import 'package:flutter/material.dart';

import '../app/theme.dart';

const modalDanger = Color(0xFFD94E64);
const modalInputTextStyle = TextStyle(fontSize: 14, color: lxInk);
const modalSupportingTextStyle = TextStyle(
  fontSize: 12,
  height: 1.4,
  color: lxMuted,
);

ThemeData appModalTheme(ThemeData base) => base.copyWith(
  dialogTheme: DialogThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(24)),
    ),
    titleTextStyle: base.textTheme.titleLarge!.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: lxInk,
    ),
    contentTextStyle: base.textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      height: 1.55,
      color: lxMuted,
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: lxGreen,
      foregroundColor: Colors.white,
      minimumSize: const Size(64, 42),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: base.textTheme.labelLarge!.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: lxMuted,
      minimumSize: const Size(48, 40),
      textStyle: base.textTheme.labelLarge!.copyWith(fontSize: 14),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFFFAFCFA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    hintStyle: modalInputTextStyle.copyWith(color: lxMuted),
    labelStyle: modalInputTextStyle.copyWith(color: lxMuted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFDDE8E0)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFDDE8E0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: lxGreen),
    ),
  ),
  listTileTheme: ListTileThemeData(
    iconColor: lxMuted,
    textColor: lxInk,
    contentPadding: EdgeInsets.symmetric(horizontal: 20),
    selectedColor: lxGreen,
    selectedTileColor: Color(0xFFEAF8F0),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
    titleTextStyle: base.textTheme.bodyLarge!.copyWith(
      fontSize: 15,
      color: lxInk,
    ),
    subtitleTextStyle: base.textTheme.bodyMedium!.copyWith(
      fontSize: 12,
      color: lxMuted,
      height: 1.4,
    ),
  ),
);

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool dangerous = false,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  barrierColor: const Color(0x52172B28),
  builder: (context) {
    var theme = appModalTheme(Theme.of(context));
    if (dangerous) {
      theme = theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: theme.filledButtonTheme.style!.copyWith(
            backgroundColor: const WidgetStatePropertyAll(modalDanger),
          ),
        ),
      );
    }
    return Theme(
      data: theme,
      child: Builder(builder: builder),
    );
  },
);

Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  String? subtitle,
  String closeLabel = '取消',
  bool showDragHandle = true,
  bool isScrollControlled = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  barrierColor: const Color(0x52172B28),
  useSafeArea: true,
  backgroundColor: Colors.white,
  elevation: 0,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (context) => Theme(
    data: appModalTheme(Theme.of(context)),
    child: Builder(
      builder: (context) {
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (MediaQuery.sizeOf(context).height * .92 - keyboard)
                    .clamp(120, double.infinity),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showDragHandle)
                    Center(
                      child: Container(
                        width: 30,
                        height: 3,
                        margin: const EdgeInsets.only(top: 9, bottom: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD5E0D9),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  if (title != null)
                    SheetHeader(
                      title: title,
                      subtitle: subtitle,
                      closeLabel: closeLabel,
                    ),
                  Flexible(
                    fit: FlexFit.loose,
                    child: MediaQuery.removeViewInsets(
                      context: context,
                      removeBottom: true,
                      child: builder(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  ),
);

class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.closeLabel = '取消',
    this.trailing,
    this.subtitleTrailing,
  });
  final String title, closeLabel;
  final String? subtitle;
  final Widget? trailing, subtitleTrailing;
  Widget _subtitle(int maxLines) => Text(
    subtitle!,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: modalSupportingTextStyle,
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: lxInk,
                ),
              ),
            ),
            trailing ??
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(closeLabel),
                ),
          ],
        ),
        if (subtitle != null)
          if (subtitleTrailing case final accessory?)
            LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  Expanded(child: _subtitle(1)),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * .7,
                    ),
                    child: accessory,
                  ),
                ],
              ),
            )
          else
            _subtitle(3),
      ],
    ),
  );
}

// Keep short option sets compact while allowing long lists to scroll.
double modalPanelHeight(
  BuildContext context,
  double contentHeight, {
  double minHeight = 200,
  double maxFraction = .65,
}) {
  final desired = contentHeight < minHeight ? minHeight : contentHeight;
  return desired.clamp(0.0, MediaQuery.sizeOf(context).height * maxFraction);
}
