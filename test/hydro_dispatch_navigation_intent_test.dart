import 'package:fishtrack/core/navigation/hydro_dispatch_navigation_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(HydroDispatchNavigationIntent.disarm);

  group('Hydro Dispatch navigation intent', () {
    test('CHE selection is consumed once', () {
      String? selectedPlantId;
      String? selectedPlantName;
      HydroDispatchNavigationIntent.arm(
        onSelected: (plantId, plantName) {
          selectedPlantId = plantId;
          selectedPlantName = plantName;
        },
      );

      HydroDispatchNavigationIntent.notifySelection(
        plantId: 'frunzaru-id',
        plantName: 'Frunzaru',
      );

      expect(selectedPlantId, 'frunzaru-id');
      expect(selectedPlantName, 'Frunzaru');
      expect(HydroDispatchNavigationIntent.isArmed, isFalse);

      HydroDispatchNavigationIntent.notifySelection(
        plantId: 'izbiceni-id',
        plantName: 'Izbiceni',
      );
      expect(selectedPlantId, 'frunzaru-id');
    });

    test('non-CHE selection cancels an armed selector', () {
      var called = false;
      HydroDispatchNavigationIntent.arm(
        onSelected: (_, _) => called = true,
      );

      HydroDispatchNavigationIntent.notifySelection();

      expect(called, isFalse);
      expect(HydroDispatchNavigationIntent.isArmed, isFalse);
    });
  });
}