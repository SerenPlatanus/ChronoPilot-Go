import 'package:flutter/material.dart';

/// Same generated artwork as the Android launcher icon.
class EclipseMark extends StatelessWidget {
  final double size;
  const EclipseMark({super.key, this.size = 64});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'ChronoPilot 日食',
    image: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * .1875),
      child: Image.asset(
        'assets/branding/eclipse.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    ),
  );
}
