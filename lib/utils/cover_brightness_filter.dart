import 'package:flutter/material.dart';

import '../models/user_manager.dart';

class CoverBrightnessFilter extends StatelessWidget {
  final Widget child;
  final bool enabled;
  final double? brightness;

  const CoverBrightnessFilter({
    super.key,
    required this.child,
    this.enabled = true,
    this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBrightness =
        brightness ?? UserManager().darkModeCoverBrightness;
    if (!enabled ||
        Theme.of(context).brightness != Brightness.dark ||
        effectiveBrightness >= 0.999) {
      return child;
    }

    return ColorFiltered(
      colorFilter: ColorFilter.matrix(_brightnessMatrix(effectiveBrightness)),
      child: child,
    );
  }

  static List<double> _brightnessMatrix(double value) {
    return <double>[
      value,
      0,
      0,
      0,
      0,
      0,
      value,
      0,
      0,
      0,
      0,
      0,
      value,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }
}
