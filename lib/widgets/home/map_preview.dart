import 'package:flutter/material.dart';

class MapPreview extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const MapPreview({super.key, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.40;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: child,
          ),
        ),
      ),
    );
  }
}
