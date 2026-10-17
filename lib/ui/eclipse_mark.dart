import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Uses the editable vector source, without bundling the large raster artwork.
class EclipseMark extends StatelessWidget {
  final double size;
  const EclipseMark({super.key, this.size = 64});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'ChronoPilot 日食',
    image: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * .1875),
      child: SvgPicture.asset(
        'assets/branding/eclipse.svg',
        width: size,
        height: size,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
      ),
    ),
  );
}
