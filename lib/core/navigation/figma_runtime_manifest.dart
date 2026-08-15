import 'app_destination.dart';

enum FigmaFrameVariant { canonical, overlay, runtimeState }

class FigmaFrameContract {
  const FigmaFrameContract({
    required this.name,
    required this.nodeId,
    required this.destination,
    required this.variant,
  });

  final String name;
  final String nodeId;
  final AppDestination destination;
  final FigmaFrameVariant variant;
}

class FigmaPrototypeConnection {
  const FigmaPrototypeConnection({
    required this.index,
    required this.sourceNodeId,
    required this.from,
    required this.to,
  });

  final int index;
  final String sourceNodeId;
  final AppDestination from;
  final AppDestination to;
}

/// Runtime contract for the approved FluviAI Figma file.
///
/// File key: 65pycGdhkI9wK5nKBgZAoZ.
/// The approved Bento Product Owner review is the visual source of truth.
/// Runtime routes remain separate from visual inventory so legacy/repeated
/// screens cannot become canonical merely because a Flutter route still exists.
abstract final class FigmaRuntimeManifest {
  static const designFileKey = '65pycGdhkI9wK5nKBgZAoZ';

  static const reviewRootNodeId = '329:3';

  /// The approved primary visual surfaces from the Bento Product Owner review.
  ///
  /// This list is intentionally small. Loading, offline, Free/Premium and
  /// paywall are runtime states of these product surfaces, not duplicate apps
  /// or parallel canonical screens. Functional Flutter routes remain owned by
  /// [AppDestinationRegistry] even when they do not have a separate primary
  /// Figma surface.
  static const approvedPrimaryFrames = <FigmaFrameContract>[
    FigmaFrameContract(
      name: 'Home',
      nodeId: '329:11',
      destination: AppDestination.home,
      variant: FigmaFrameVariant.canonical,
    ),
    FigmaFrameContract(
      name: 'Full Map',
      nodeId: '329:293',
      destination: AppDestination.map,
      variant: FigmaFrameVariant.canonical,
    ),
    FigmaFrameContract(
      name: 'Quick Add / Capture',
      nodeId: '329:365',
      destination: AppDestination.addCatch,
      variant: FigmaFrameVariant.overlay,
    ),
    FigmaFrameContract(
      name: 'Activity',
      nodeId: '329:425',
      destination: AppDestination.activity,
      variant: FigmaFrameVariant.canonical,
    ),
    FigmaFrameContract(
      name: 'Utilities',
      nodeId: '329:518',
      destination: AppDestination.utilities,
      variant: FigmaFrameVariant.canonical,
    ),
    FigmaFrameContract(
      name: 'Water',
      nodeId: '329:629',
      destination: AppDestination.water,
      variant: FigmaFrameVariant.canonical,
    ),
    FigmaFrameContract(
      name: 'Weather',
      nodeId: '329:697',
      destination: AppDestination.weather,
      variant: FigmaFrameVariant.canonical,
    ),
    FigmaFrameContract(
      name: 'FluviScore',
      nodeId: '329:769',
      destination: AppDestination.fluvi,
      variant: FigmaFrameVariant.canonical,
    ),
    FigmaFrameContract(
      name: 'Community',
      nodeId: '329:836',
      destination: AppDestination.community,
      variant: FigmaFrameVariant.canonical,
    ),
    FigmaFrameContract(
      name: 'Reports',
      nodeId: '329:898',
      destination: AppDestination.myReports,
      variant: FigmaFrameVariant.canonical,
    ),
    FigmaFrameContract(
      name: 'Settings / Legal / Help',
      nodeId: '437:5',
      destination: AppDestination.settings,
      variant: FigmaFrameVariant.canonical,
    ),
  ];

  // Compatibility alias for code that still uses the previous field name.
  static const canonical = approvedPrimaryFrames;

  static const allOfficialFrames = approvedPrimaryFrames;

  /// Executable Flutter route graph preserved independently of visual inventory.
  /// Source-node migration is handled separately from this visual-contract change.
  static const connections = <FigmaPrototypeConnection>[
    FigmaPrototypeConnection(
      index: 1,
      sourceNodeId: '5:195',
      from: AppDestination.home,
      to: AppDestination.map,
    ),
    FigmaPrototypeConnection(
      index: 2,
      sourceNodeId: '5:195',
      from: AppDestination.home,
      to: AppDestination.water,
    ),
    FigmaPrototypeConnection(
      index: 3,
      sourceNodeId: '5:195',
      from: AppDestination.home,
      to: AppDestination.weather,
    ),
    FigmaPrototypeConnection(
      index: 4,
      sourceNodeId: '5:195',
      from: AppDestination.home,
      to: AppDestination.fluvi,
    ),
    FigmaPrototypeConnection(
      index: 5,
      sourceNodeId: '5:195',
      from: AppDestination.home,
      to: AppDestination.community,
    ),
    FigmaPrototypeConnection(
      index: 6,
      sourceNodeId: '5:444',
      from: AppDestination.map,
      to: AppDestination.search,
    ),
    FigmaPrototypeConnection(
      index: 7,
      sourceNodeId: '5:444',
      from: AppDestination.map,
      to: AppDestination.addReport,
    ),
    FigmaPrototypeConnection(
      index: 8,
      sourceNodeId: '2280:2',
      from: AppDestination.community,
      to: AppDestination.reportDetail,
    ),
    FigmaPrototypeConnection(
      index: 9,
      sourceNodeId: '2387:2',
      from: AppDestination.reportDetail,
      to: AppDestination.reportConfirmed,
    ),
    FigmaPrototypeConnection(
      index: 10,
      sourceNodeId: '2432:2',
      from: AppDestination.catches,
      to: AppDestination.catchDetail,
    ),
    FigmaPrototypeConnection(
      index: 11,
      sourceNodeId: '2450:163',
      from: AppDestination.home,
      to: AppDestination.addCatch,
    ),
    FigmaPrototypeConnection(
      index: 12,
      sourceNodeId: '2436:2',
      from: AppDestination.favorites,
      to: AppDestination.water,
    ),
    FigmaPrototypeConnection(
      index: 13,
      sourceNodeId: '2440:2',
      from: AppDestination.alerts,
      to: AppDestination.newAlert,
    ),
    FigmaPrototypeConnection(
      index: 14,
      sourceNodeId: '2445:2',
      from: AppDestination.profile,
      to: AppDestination.settings,
    ),
    FigmaPrototypeConnection(
      index: 15,
      sourceNodeId: '2445:2',
      from: AppDestination.profile,
      to: AppDestination.accountSecurity,
    ),
    FigmaPrototypeConnection(
      index: 16,
      sourceNodeId: '2445:2',
      from: AppDestination.profile,
      to: AppDestination.premium,
    ),
    FigmaPrototypeConnection(
      index: 17,
      sourceNodeId: '2445:2',
      from: AppDestination.profile,
      to: AppDestination.legal,
    ),
    FigmaPrototypeConnection(
      index: 18,
      sourceNodeId: '2448:2',
      from: AppDestination.premium,
      to: AppDestination.restore,
    ),
    FigmaPrototypeConnection(
      index: 19,
      sourceNodeId: '5:295',
      from: AppDestination.water,
      to: AppDestination.newAlert,
    ),
    FigmaPrototypeConnection(
      index: 20,
      sourceNodeId: '2433:2',
      from: AppDestination.addCatch,
      to: AppDestination.myCatches,
    ),
    FigmaPrototypeConnection(
      index: 21,
      sourceNodeId: '2255:2',
      from: AppDestination.fluvi,
      to: AppDestination.askFluvi,
    ),
    FigmaPrototypeConnection(
      index: 22,
      sourceNodeId: '2448:2',
      from: AppDestination.premium,
      to: AppDestination.premiumRestored,
    ),
  ];
}
