import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    required this.size,
    this.borderRadius = 0.22,
    this.shadow = false,
  });

  final double size;
  final double borderRadius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * borderRadius);
    final child = ClipRRect(
      borderRadius: radius,
      child: SvgPicture.asset(
        'assets/logo.svg',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
    if (!shadow) return child;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: size * 0.2,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: child,
    );
  }
}
