import 'dart:ui';

import 'package:flutter/material.dart';

import '../home/map_preview.dart';

class HomePremiumMap extends StatelessWidget {
  const HomePremiumMap({super.key, this.onTap, this.child});

  final VoidCallback? onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        fit: StackFit.expand,
        children: [
          MapPreview(
            onTap: onTap,
            child: child ?? Container(color: const Color(0xFF16212B)),
          ),

          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(.06),
                    Colors.transparent,
                    Colors.black.withOpacity(.28),
                  ],
                ),
              ),
            ),
          ),

          // SEARCH
          Positioned(
            left: 12,
            top: 10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  width: MediaQuery.of(context).size.width * .68,
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.35),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white.withOpacity(.08)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.search, size: 18, color: Colors.white70),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Search location...",
                          style: TextStyle(color: Colors.white60, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // FLOATING BUTTONS
          Positioned(
            right: 12,
            top: 72,
            child: Column(
              children: const [
                _FloatingButton(Icons.my_location_rounded),
                SizedBox(height: 12),
                _FloatingButton(Icons.layers_rounded),
                SizedBox(height: 12),
                _FloatingButton(Icons.filter_alt_rounded),
              ],
            ),
          ),

          // LOCATION
          Positioned(
            left: 12,
            bottom: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.35),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on,
                        color: Color(0xFF67D04B),
                        size: 16,
                      ),
                      SizedBox(width: 5),
                      Text(
                        "Current Location",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // LIVE
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF67D04B),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sensors, size: 14, color: Colors.black),
                  SizedBox(width: 5),
                  Text(
                    "LIVE",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingButton extends StatelessWidget {
  const _FloatingButton(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.black.withOpacity(.32),
          child: InkWell(
            onTap: () {},
            child: SizedBox(
              width: 54,
              height: 54,
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}
