import 'package:flutter/material.dart';

/// GDS logo: a calendar page with a ball on it. Yellow and blue only. Drawn in code, no image file.
class GdsLogo extends StatefulWidget {
  final double size;
  final bool spin; // turns while the app is updating
  const GdsLogo({super.key, this.size = 48, this.spin = false});
  @override
  State<GdsLogo> createState() => _GdsLogoState();
}

class _GdsLogoState extends State<GdsLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.spin) _c.repeat();
  }

  @override
  void didUpdateWidget(GdsLogo old) {
    super.didUpdateWidget(old);
    if (widget.spin && !_c.isAnimating) _c.repeat();
    if (!widget.spin && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = CustomPaint(size: Size.square(widget.size), painter: _LogoPainter());
    return widget.spin ? RotationTransition(turns: _c, child: logo) : logo;
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final w = s.width;
    final blue = Paint()..color = const Color(0xFF0B3D91);
    final yellow = Paint()..color = const Color(0xFFFFC400);
    final white = Paint()..color = Colors.white;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, w), Radius.circular(w * .22)), blue);
    final card = RRect.fromRectAndRadius(Rect.fromLTWH(w * .17, w * .25, w * .66, w * .58), Radius.circular(w * .08));
    c.drawRRect(card, white);
    c.save();
    c.clipRRect(card);
    c.drawRect(Rect.fromLTWH(w * .17, w * .25, w * .66, w * .16), yellow);
    c.restore();
    for (final x in [.35, .65]) {
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(w * x - w * .028, w * .16, w * .056, w * .14), Radius.circular(w * .028)),
        yellow,
      );
    }
    c.drawCircle(Offset(w * .5, w * .63), w * .15, blue);
    c.drawCircle(Offset(w * .5, w * .63), w * .06, yellow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
