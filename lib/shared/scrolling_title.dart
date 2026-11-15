import 'package:flutter/material.dart';

/// A single accessible title; only overflowing text moves, with pauses at each end.
class ScrollingTitle extends StatefulWidget {
  const ScrollingTitle({super.key, required this.text});
  final String text;
  @override
  State<ScrollingTitle> createState() => _ScrollingTitleState();
}

class _ScrollingTitleState extends State<ScrollingTitle>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);
  double _distance = -1;
  Animation<double> _progress = const AlwaysStoppedAnimation(0);
  int _generation = 0;

  @override
  void didUpdateWidget(covariant ScrollingTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _distance = -1;
  }

  void _configure(double distance) {
    if (_distance == distance) return;
    _distance = distance;
    final generation = ++_generation;
    _controller.stop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      _controller.value = 0;
      if (distance <= 0) return;
      final travelMs = (distance / 28 * 1000).round().clamp(1, 60000);
      _controller.duration = Duration(milliseconds: travelMs + 2000);
      _progress = TweenSequence<double>([
        TweenSequenceItem(tween: ConstantTween(0), weight: 1000),
        TweenSequenceItem(
          tween: Tween(begin: 0, end: 1),
          weight: travelMs.toDouble(),
        ),
        TweenSequenceItem(tween: ConstantTween(1), weight: 1000),
      ]).animate(_controller);
      _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style
        .copyWith(fontSize: 17, fontWeight: FontWeight.w600);
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final width = painter.width;
        final height = painter.height;
        painter.dispose();
        final distance = (width - constraints.maxWidth).clamp(
          0.0,
          double.infinity,
        );
        _configure(reduceMotion ? 0 : distance);
        if (distance == 0 || reduceMotion) {
          return Text(
            widget.text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }
        return Semantics(
          label: widget.text,
          child: ExcludeSemantics(
            child: ClipRect(
              child: SizedBox(
                height: height,
                child: AnimatedBuilder(
                  animation: _controller,
                  child: Text(
                    widget.text,
                    style: style,
                    maxLines: 1,
                    softWrap: false,
                  ),
                  builder: (context, child) => Transform.translate(
                    offset: Offset(
                      (direction == TextDirection.ltr ? -1 : 1) *
                          distance *
                          _progress.value,
                      0,
                    ),
                    child: OverflowBox(
                      alignment: AlignmentDirectional.centerStart,
                      minWidth: width,
                      maxWidth: width,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
