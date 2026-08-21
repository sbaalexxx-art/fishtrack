import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/context/selected_context.dart';
import '../core/navigation/app_navigator.dart';
import '../l10n/l10n.dart';
import '../models/station.dart';
import '../models/saved_item.dart';
import '../services/favorite_stations_service.dart';
import '../services/saved_items_service.dart';
import '../services/water_service.dart';
import 'station_details_page.dart';

enum _FavoriteCategory { all, places, stations, reports, catches }

enum _FavoriteStationAction { open, remove }

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final FavoriteStationsService _service = const FavoriteStationsService();
  final WaterService _waterService = WaterService();
  final SavedItemsService _savedItemsService = const SavedItemsService();

  late Future<_FavoritesData> _favorites;
  final Set<String> _removingStationIds = <String>{};
  _FavoriteCategory _selectedCategory = _FavoriteCategory.all;

  @override
  void initState() {
    super.initState();
    _favorites = _load();
    FavoriteStationsService.revision.addListener(_reload);
    SavedItemsService.revision.addListener(_reload);
  }

  @override
  void dispose() {
    FavoriteStationsService.revision.removeListener(_reload);
    SavedItemsService.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _favorites = _load());
  }

  Future<_FavoritesData> _load() async {
    if (!_service.isAuthenticated) {
      throw const FavoriteException('Please sign in to view your favourites.');
    }

    final results = await Future.wait<Object>([
      _waterService.getStations(),
      _service.getFavoriteIds(),
      _savedItemsService.getItems(),
    ]);
    final stations = results[0] as List<Station>;
    final ids = results[1] as Set<String>;
    final savedItems = results[2] as List<SavedItem>;

    final favorites =
        stations
            .where((station) => ids.contains(station.id))
            .toList(growable: false)
          ..sort((a, b) => a.name.compareTo(b.name));
    return _FavoritesData(stations: favorites, savedItems: savedItems);
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _favorites = future);
    await future;
  }

  Future<void> _removeStation(Station station) async {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF16222D),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          height: 1.35,
        ),
        title: Text(isRo ? 'Elimini din Favorite?' : 'Remove from Favorites?'),
        content: Text(
          isRo
              ? '${station.name} nu va mai apărea în colecția ta.'
              : '${station.name} will no longer appear in your collection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(isRo ? 'Anulează' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isRo ? 'Elimină' : 'Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _removingStationIds.add(station.id));
    try {
      await _service.setFavorite(station.id, favorite: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRo
                ? '${station.name} a fost eliminată din Favorite.'
                : '${station.name} was removed from Favorites.',
          ),
        ),
      );
    } on FavoriteException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _removingStationIds.remove(station.id));
      }
    }
  }

  Future<void> _removeSavedItem(SavedItem item) async {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    try {
      await _savedItemsService.remove(
        type: item.type,
        referenceId: item.referenceId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRo
                ? '${item.title} a fost eliminat.'
                : '${item.title} was removed.',
          ),
        ),
      );
    } on SavedItemsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _openSavedItem(SavedItem item) async {
    final lat = item.latitude;
    final lng = item.longitude;
    if (lat == null || lng == null) return;
    try {
      ProviderScope.containerOf(context, listen: false)
          .read(selectedContextProvider.notifier)
          .select(
            SelectedContext(
              locationName: item.title,
              latitude: lat,
              longitude: lng,
              placeId: item.referenceId,
              selectedAt: DateTime.now(),
            ),
          );
    } on StateError {
      // Isolated widget tests may omit ProviderScope.
    }
    if (!mounted) return;
    await AppNavigator.openPath<void>(context, '/map');
  }

  void _openStation(Station station) {
    try {
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(selectedContextProvider.notifier).selectStation(station);
    } on StateError {
      // Widget tests and isolated previews may intentionally omit ProviderScope.
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StationDetailsPage(station: station),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';

    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1115),
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        title: Text(
          context.l10n.favorites,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _FavoritesHero(isRo: isRo),
            _FavoriteCategorySelector(
              selectedCategory: _selectedCategory,
              isRo: isRo,
              onSelected: (category) {
                setState(() => _selectedCategory = category);
              },
            ),
            const SizedBox(height: 4),
            Expanded(
              child: FutureBuilder<_FavoritesData>(
                future: _favorites,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _FavoritesLoading();
                  }
                  if (snapshot.hasError) {
                    return _FavoriteMessage(
                      icon: Icons.cloud_off_rounded,
                      title: !_service.isAuthenticated
                          ? context.l10n.signInForFavorites
                          : context.l10n.favoritesUnavailable,
                      subtitle: isRo
                          ? 'Trage în jos sau încearcă din nou.'
                          : 'Pull down or try again.',
                      onRetry: _refresh,
                    );
                  }

                  final data = snapshot.data ?? const _FavoritesData();
                  final stations =
                      _selectedCategory == _FavoriteCategory.all ||
                          _selectedCategory == _FavoriteCategory.stations
                      ? data.stations
                      : const <Station>[];
                  final wantedType = switch (_selectedCategory) {
                    _FavoriteCategory.places => 'place',
                    _FavoriteCategory.reports => 'report',
                    _FavoriteCategory.catches => 'catch',
                    _ => null,
                  };
                  final savedItems = wantedType == null
                      ? (_selectedCategory == _FavoriteCategory.all
                            ? data.savedItems
                            : const <SavedItem>[])
                      : data.savedItems
                            .where((item) => item.type == wantedType)
                            .toList(growable: false);

                  if (stations.isEmpty && savedItems.isEmpty) {
                    return _FavoriteMessage(
                      icon: Icons.bookmark_border_rounded,
                      title: isRo
                          ? 'Nu ai elemente în această categorie'
                          : 'No items in this category',
                      subtitle: isRo
                          ? 'Salvează locuri, stații, rapoarte sau capturi din fluxurile lor reale.'
                          : 'Save places, stations, reports or catches from their real flows.',
                      onRetry: _refresh,
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    color: const Color(0xFF12D8D6),
                    backgroundColor: const Color(0xFF16222D),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      children: [
                        if (stations.isNotEmpty) ...[
                          _FavoritesSectionHeader(
                            count: stations.length,
                            isRo: isRo,
                          ),
                          const SizedBox(height: 10),
                          for (final station in stations)
                            _FavoriteStationCard(
                              station: station,
                              isRo: isRo,
                              removing: _removingStationIds.contains(
                                station.id,
                              ),
                              onOpen: () => _openStation(station),
                              onRemove: () => _removeStation(station),
                            ),
                        ],
                        if (stations.isNotEmpty && savedItems.isNotEmpty)
                          const SizedBox(height: 18),
                        if (savedItems.isNotEmpty) ...[
                          _SavedItemsSectionHeader(
                            count: savedItems.length,
                            isRo: isRo,
                          ),
                          const SizedBox(height: 10),
                          for (final item in savedItems)
                            _SavedItemCard(
                              item: item,
                              isRo: isRo,
                              onOpen: () => _openSavedItem(item),
                              onRemove: () => _removeSavedItem(item),
                            ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoritesData {
  const _FavoritesData({
    this.stations = const <Station>[],
    this.savedItems = const <SavedItem>[],
  });

  final List<Station> stations;
  final List<SavedItem> savedItems;
}

class _SavedItemsSectionHeader extends StatelessWidget {
  const _SavedItemsSectionHeader({required this.count, required this.isRo});
  final int count;
  final bool isRo;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.bookmarks_rounded, size: 18, color: Color(0xFF12D8D6)),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          isRo ? 'Elemente salvate' : 'Saved items',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      Text(
        '$count',
        style: const TextStyle(
          color: Colors.white54,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _SavedItemCard extends StatelessWidget {
  const _SavedItemCard({
    required this.item,
    required this.isRo,
    required this.onOpen,
    required this.onRemove,
  });

  final SavedItem item;
  final bool isRo;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  IconData get _icon => switch (item.type) {
    'report' => Icons.campaign_rounded,
    'catch' => Icons.phishing_rounded,
    _ => Icons.place_rounded,
  };

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF17212A),
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      onTap: onOpen,
      leading: Icon(_icon, color: const Color(0xFF12D8D6)),
      title: Text(
        item.title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: item.subtitle == null
          ? Text(
              item.latitude != null && item.longitude != null
                  ? '${item.latitude!.toStringAsFixed(3)}, ${item.longitude!.toStringAsFixed(3)}'
                  : (isRo ? 'Salvat' : 'Saved'),
              style: const TextStyle(color: Colors.white54),
            )
          : Text(
              item.subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54),
            ),
      trailing: IconButton(
        tooltip: isRo ? 'Elimină' : 'Remove',
        onPressed: onRemove,
        icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54),
      ),
    ),
  );
}

class _FavoritesHero extends StatelessWidget {
  const _FavoritesHero({required this.isRo});

  final bool isRo;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF162B38), Color(0xFF101C26)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF12D8D6).withValues(alpha: .24),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF12D8D6).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.bookmark_rounded, color: Color(0xFF12D8D6)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRo ? 'Colecția ta personală' : 'Your personal collection',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isRo
                      ? 'Locuri, stații, rapoarte și capturi salvate de tine.'
                      : 'Places, stations, reports and catches saved by you.',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteCategorySelector extends StatelessWidget {
  const _FavoriteCategorySelector({
    required this.selectedCategory,
    required this.isRo,
    required this.onSelected,
  });

  final _FavoriteCategory selectedCategory;
  final bool isRo;
  final ValueChanged<_FavoriteCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 28, 0),
        itemCount: _FavoriteCategory.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _FavoriteCategory.values[index];
          final selected = category == selectedCategory;
          final metadata = _FavoriteCategoryMetadata(category, isRo: isRo);

          return ChoiceChip(
            selected: selected,
            onSelected: (_) => onSelected(category),
            avatar: Icon(
              metadata.icon,
              size: 16,
              color: selected ? const Color(0xFF07131C) : metadata.color,
            ),
            label: Text(metadata.label),
            labelStyle: TextStyle(
              color: selected ? const Color(0xFF07131C) : Colors.white70,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
            backgroundColor: const Color(0xFF17212A),
            selectedColor: const Color(0xFF12D8D6),
            side: BorderSide(
              color: selected
                  ? const Color(0xFF12D8D6)
                  : Colors.white.withValues(alpha: .10),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
            showCheckmark: false,
          );
        },
      ),
    );
  }
}

class _FavoritesSectionHeader extends StatelessWidget {
  const _FavoritesSectionHeader({required this.count, required this.isRo});

  final int count;
  final bool isRo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.water_drop_rounded,
          size: 18,
          color: Color(0xFF2196F3),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            isRo ? 'Stații de măsurare' : 'Monitoring stations',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _FavoriteStationCard extends StatelessWidget {
  const _FavoriteStationCard({
    required this.station,
    required this.isRo,
    required this.removing,
    required this.onOpen,
    required this.onRemove,
  });

  final Station station;
  final bool isRo;
  final bool removing;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final level = station.hasWaterLevel
        ? '${station.level.toStringAsFixed(0)} ${station.waterLevelUnit}'
        : (isRo ? 'Nivel indisponibil' : 'Level unavailable');
    final river = station.river.trim();
    final subtitle = river.isEmpty ? level : '$river · $level';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: removing ? null : onOpen,
          borderRadius: BorderRadius.circular(17),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF162631), Color(0xFF101B24)],
              ),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: const Color(0xFF2196F3).withValues(alpha: .20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.water_drop_rounded,
                    color: Color(0xFF2196F3),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isRo ? 'Stație de măsurare' : 'Monitoring station',
                        style: const TextStyle(
                          color: Color(0xFF2196F3),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_FavoriteStationAction>(
                  enabled: !removing,
                  tooltip: isRo ? 'Acțiuni' : 'Actions',
                  color: const Color(0xFF17232D),
                  surfaceTintColor: Colors.transparent,
                  icon: removing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 1.8),
                        )
                      : const Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white54,
                          size: 21,
                        ),
                  onSelected: (action) {
                    switch (action) {
                      case _FavoriteStationAction.open:
                        onOpen();
                      case _FavoriteStationAction.remove:
                        onRemove();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<_FavoriteStationAction>(
                      value: _FavoriteStationAction.open,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.open_in_new_rounded,
                            color: Color(0xFF12D8D6),
                            size: 19,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isRo ? 'Deschide detaliile' : 'Open details',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem<_FavoriteStationAction>(
                      value: _FavoriteStationAction.remove,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.bookmark_remove_rounded,
                            color: Color(0xFFE57373),
                            size: 19,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isRo
                                ? 'Elimină din Favorite'
                                : 'Remove from Favorites',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteMessage extends StatelessWidget {
  const _FavoriteMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRetry,
      color: const Color(0xFF12D8D6),
      backgroundColor: const Color(0xFF16222D),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * .52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white38, size: 52),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.l10n.refresh),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _EmptyCategoryMessage extends StatelessWidget {
  const _EmptyCategoryMessage({
    required this.category,
    required this.isRo,
    required this.onRefresh,
  });

  final _FavoriteCategory category;
  final bool isRo;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final metadata = _FavoriteCategoryMetadata(category, isRo: isRo);
    return _FavoriteMessage(
      icon: metadata.icon,
      title: isRo
          ? 'Nu ai ${metadata.label.toLowerCase()} favorite'
          : 'No favorite ${metadata.label.toLowerCase()}',
      subtitle: isRo
          ? 'Când salvezi un element din hartă sau din pagina lui de detalii, va apărea aici.'
          : 'When you save an item from the map or its details page, it will appear here.',
      onRetry: onRefresh,
    );
  }
}

class _FavoritesLoading extends StatelessWidget {
  const _FavoritesLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        Container(
          width: 140,
          height: 18,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < 4; index++) ...[
          Container(
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(17),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _FavoriteCategoryMetadata {
  const _FavoriteCategoryMetadata(this.category, {required this.isRo});

  final _FavoriteCategory category;
  final bool isRo;

  IconData get icon => switch (category) {
    _FavoriteCategory.all => Icons.grid_view_rounded,
    _FavoriteCategory.places => Icons.location_on_rounded,
    _FavoriteCategory.stations => Icons.water_drop_rounded,
    _FavoriteCategory.reports => Icons.campaign_rounded,
    _FavoriteCategory.catches => Icons.set_meal_rounded,
  };

  Color get color => switch (category) {
    _FavoriteCategory.all => const Color(0xFF12D8D6),
    _FavoriteCategory.places => const Color(0xFFFFB74D),
    _FavoriteCategory.stations => const Color(0xFF2196F3),
    _FavoriteCategory.reports => const Color(0xFFFF7043),
    _FavoriteCategory.catches => const Color(0xFF66BB6A),
  };

  String get label => switch (category) {
    _FavoriteCategory.all => isRo ? 'Toate' : 'All',
    _FavoriteCategory.places => isRo ? 'Locuri' : 'Places',
    _FavoriteCategory.stations => isRo ? 'Stații' : 'Stations',
    _FavoriteCategory.reports => isRo ? 'Rapoarte' : 'Reports',
    _FavoriteCategory.catches => isRo ? 'Capturi' : 'Catches',
  };
}
