import 'package:flutter/material.dart';

class PremiumBottomNavigation extends StatelessWidget {
  const PremiumBottomNavigation({
    super.key,
    this.currentIndex = 0,
    this.onItemSelected,
    this.onAddCatch,
  });

  final int currentIndex;
  final ValueChanged<int>? onItemSelected;
  final VoidCallback? onAddCatch;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF171C24),
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            _item(index: 0, icon: Icons.home_rounded, label: 'Home'),
            _item(index: 1, icon: Icons.map_rounded, label: 'Map'),

            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: onAddCatch,
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF67D04B),
                    ),
                    child: const Icon(Icons.add, color: Colors.black, size: 34),
                  ),
                ),
              ),
            ),

            _item(index: 2, icon: Icons.bar_chart_rounded, label: 'Reports'),
            _item(index: 3, icon: Icons.person_rounded, label: 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _item({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final bool selected = currentIndex == index;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onItemSelected?.call(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 24,
                color: selected ? const Color(0xFF67D04B) : Colors.white60,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? const Color(0xFF67D04B) : Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
