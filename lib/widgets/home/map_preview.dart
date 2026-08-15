import 'package:flutter/material.dart';

import '../../core/theme/app_dimensions.dart';

class MapPreview extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const MapPreview({super.key, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppDimensions.sectionSpacing,
        8,
        AppDimensions.sectionSpacing,
        10,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
        child: SizedBox(
          height: AppDimensions.mapHeight(context),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFF1B1B1B)),
              ),

              child,

              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: .08),
                        Colors.transparent,
                        Colors.black.withValues(alpha: .18),
                      ],
                    ),
                  ),
                ),
              ),

              if (onTap != null)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
