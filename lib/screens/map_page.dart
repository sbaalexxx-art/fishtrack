import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/station.dart';
import '../services/station_filter_service.dart';
import '../services/water_service.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final WaterService _waterService = WaterService();
  final StationFilterService _filterService = StationFilterService.instance;
  late final Future<List<Station>> _stationsFuture;

  @override
  void initState() {
    super.initState();
    _stationsFuture = _waterService.getStations();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Harta Apelor'), centerTitle: true),
      body: FutureBuilder<List<Station>>(
        future: _stationsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Stațiile nu au putut fi încărcate.'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return ValueListenableBuilder<StationFilters>(
            valueListenable: _filterService.filters,
            builder: (context, filters, _) =>
                _StationMap(stations: _filterService.apply(snapshot.data!)),
          );
        },
      ),
    );
  }
}

class _StationMap extends StatelessWidget {
  const _StationMap({required this.stations});

  final List<Station> stations;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(45.5, 27.2),
        initialZoom: 6.8,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.fishtrack.app',
        ),
        MarkerLayer(
          markers: stations
              .map(
                (station) => Marker(
                  point: LatLng(station.latitude, station.longitude),
                  width: 50,
                  height: 50,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 38,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
