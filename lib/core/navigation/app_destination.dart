import 'package:flutter/material.dart';

enum AppDestination {
  home,
  map,
  contextualMap,
  activity,
  utilities,
  search,
  notifications,
  notificationPreferences,
  water,
  station,
  river,
  reservoir,
  hydropower,
  weather,
  fluvi,
  askFluvi,
  community,
  reportDetail,
  reportConfirmed,
  addReport,
  myReports,
  catches,
  addCatch,
  catchDetail,
  myCatches,
  journal,
  favorites,
  favoriteCollection,
  alerts,
  newAlert,
  editAlert,
  toolkit,
  permit,
  regulations,
  safety,
  profile,
  accountSecurity,
  recovery,
  premium,
  restore,
  premiumRestored,
  support,
  privacy,
  terms,
  licences,
  about,
  moderation,
  aiTransparency,
  legal,
  settings,
}

class AppDestinationDefinition {
  const AppDestinationDefinition({
    required this.destination,
    required this.path,
    required this.titleRo,
    required this.titleEn,
    required this.icon,
    this.requiresEntity = false,
  });

  final AppDestination destination;
  final String path;
  final String titleRo;
  final String titleEn;
  final IconData icon;
  final bool requiresEntity;

  String title(bool isRomanian) => isRomanian ? titleRo : titleEn;
}

abstract final class AppDestinationRegistry {
  static const definitions = <AppDestination, AppDestinationDefinition>{
    AppDestination.home: AppDestinationDefinition(
      destination: AppDestination.home,
      path: '/home',
      titleRo: 'Acasă',
      titleEn: 'Home',
      icon: Icons.home_rounded,
    ),
    AppDestination.map: AppDestinationDefinition(
      destination: AppDestination.map,
      path: '/map',
      titleRo: 'Hartă',
      titleEn: 'Map',
      icon: Icons.map_rounded,
    ),
    AppDestination.contextualMap: AppDestinationDefinition(
      destination: AppDestination.contextualMap,
      path: '/map/contextual',
      titleRo: 'Hartă contextuală',
      titleEn: 'Contextual map',
      icon: Icons.location_on_rounded,
    ),
    AppDestination.activity: AppDestinationDefinition(
      destination: AppDestination.activity,
      path: '/activity',
      titleRo: 'Activitate',
      titleEn: 'Activity',
      icon: Icons.timeline_rounded,
    ),
    AppDestination.utilities: AppDestinationDefinition(
      destination: AppDestination.utilities,
      path: '/utilities',
      titleRo: 'Utilități',
      titleEn: 'Utilities',
      icon: Icons.grid_view_rounded,
    ),
    AppDestination.search: AppDestinationDefinition(
      destination: AppDestination.search,
      path: '/search',
      titleRo: 'Căutare',
      titleEn: 'Search',
      icon: Icons.search_rounded,
    ),
    AppDestination.notifications: AppDestinationDefinition(
      destination: AppDestination.notifications,
      path: '/notifications',
      titleRo: 'Notificări',
      titleEn: 'Notifications',
      icon: Icons.notifications_rounded,
    ),
    AppDestination.notificationPreferences: AppDestinationDefinition(
      destination: AppDestination.notificationPreferences,
      path: '/settings/notifications',
      titleRo: 'Preferințe notificări',
      titleEn: 'Notification preferences',
      icon: Icons.tune_rounded,
    ),
    AppDestination.water: AppDestinationDefinition(
      destination: AppDestination.water,
      path: '/water/:entityId',
      titleRo: 'Centrul apei',
      titleEn: 'Water hub',
      icon: Icons.water_rounded,
      requiresEntity: true,
    ),
    AppDestination.station: AppDestinationDefinition(
      destination: AppDestination.station,
      path: '/stations/:entityId',
      titleRo: 'Stație hidrometrică',
      titleEn: 'Water station',
      icon: Icons.speed_rounded,
      requiresEntity: true,
    ),
    AppDestination.river: AppDestinationDefinition(
      destination: AppDestination.river,
      path: '/rivers/:entityId',
      titleRo: 'Râu',
      titleEn: 'River',
      icon: Icons.waves_rounded,
      requiresEntity: true,
    ),
    AppDestination.reservoir: AppDestinationDefinition(
      destination: AppDestination.reservoir,
      path: '/reservoirs/:entityId',
      titleRo: 'Acumulare',
      titleEn: 'Reservoir',
      icon: Icons.waves_rounded,
      requiresEntity: true,
    ),
    AppDestination.hydropower: AppDestinationDefinition(
      destination: AppDestination.hydropower,
      path: '/hydropower/:entityId',
      titleRo: 'Hidrocentrală',
      titleEn: 'Hydropower',
      icon: Icons.electric_bolt_rounded,
      requiresEntity: true,
    ),
    AppDestination.weather: AppDestinationDefinition(
      destination: AppDestination.weather,
      path: '/weather/:entityId',
      titleRo: 'Vreme și solunar',
      titleEn: 'Weather & solunar',
      icon: Icons.cloud_rounded,
    ),
    AppDestination.fluvi: AppDestinationDefinition(
      destination: AppDestination.fluvi,
      path: '/fluvi/:entityId',
      titleRo: 'Fluvi Hub',
      titleEn: 'Fluvi Hub',
      icon: Icons.auto_awesome_rounded,
    ),
    AppDestination.askFluvi: AppDestinationDefinition(
      destination: AppDestination.askFluvi,
      path: '/ask-fluvi',
      titleRo: 'Întreabă Fluvi',
      titleEn: 'Ask Fluvi',
      icon: Icons.chat_bubble_rounded,
    ),
    AppDestination.community: AppDestinationDefinition(
      destination: AppDestination.community,
      path: '/community',
      titleRo: 'Comunitate',
      titleEn: 'Community',
      icon: Icons.groups_rounded,
    ),
    AppDestination.reportDetail: AppDestinationDefinition(
      destination: AppDestination.reportDetail,
      path: '/reports/:reportId',
      titleRo: 'Detaliu raport',
      titleEn: 'Report detail',
      icon: Icons.campaign_rounded,
      requiresEntity: true,
    ),
    AppDestination.reportConfirmed: AppDestinationDefinition(
      destination: AppDestination.reportConfirmed,
      path: '/reports/:reportId/confirmed',
      titleRo: 'Raport confirmat',
      titleEn: 'Report confirmed',
      icon: Icons.verified_rounded,
      requiresEntity: true,
    ),
    AppDestination.addReport: AppDestinationDefinition(
      destination: AppDestination.addReport,
      path: '/reports/new',
      titleRo: 'Raport nou',
      titleEn: 'New report',
      icon: Icons.add_location_alt_rounded,
    ),
    AppDestination.myReports: AppDestinationDefinition(
      destination: AppDestination.myReports,
      path: '/me/reports',
      titleRo: 'Rapoartele mele',
      titleEn: 'My reports',
      icon: Icons.inventory_2_rounded,
    ),
    AppDestination.catches: AppDestinationDefinition(
      destination: AppDestination.catches,
      path: '/catches',
      titleRo: 'Capturi',
      titleEn: 'Catches',
      icon: Icons.set_meal_rounded,
    ),
    AppDestination.addCatch: AppDestinationDefinition(
      destination: AppDestination.addCatch,
      path: '/catches/new',
      titleRo: 'Adaugă captură',
      titleEn: 'Add catch',
      icon: Icons.add_a_photo_rounded,
    ),
    AppDestination.catchDetail: AppDestinationDefinition(
      destination: AppDestination.catchDetail,
      path: '/catches/:catchId',
      titleRo: 'Detaliu captură',
      titleEn: 'Catch detail',
      icon: Icons.set_meal_rounded,
      requiresEntity: true,
    ),
    AppDestination.myCatches: AppDestinationDefinition(
      destination: AppDestination.myCatches,
      path: '/me/catches',
      titleRo: 'Capturile mele',
      titleEn: 'My catches',
      icon: Icons.photo_library_rounded,
    ),
    AppDestination.journal: AppDestinationDefinition(
      destination: AppDestination.journal,
      path: '/journal',
      titleRo: 'Jurnal',
      titleEn: 'Journal',
      icon: Icons.menu_book_rounded,
    ),
    AppDestination.favorites: AppDestinationDefinition(
      destination: AppDestination.favorites,
      path: '/favorites',
      titleRo: 'Apele mele',
      titleEn: 'My waters',
      icon: Icons.bookmark_rounded,
    ),
    AppDestination.favoriteCollection: AppDestinationDefinition(
      destination: AppDestination.favoriteCollection,
      path: '/favorites/:collectionId',
      titleRo: 'Colecție',
      titleEn: 'Collection',
      icon: Icons.folder_special_rounded,
      requiresEntity: true,
    ),
    AppDestination.alerts: AppDestinationDefinition(
      destination: AppDestination.alerts,
      path: '/alerts',
      titleRo: 'Alerte și reguli',
      titleEn: 'Alerts & rules',
      icon: Icons.notifications_active_rounded,
    ),
    AppDestination.newAlert: AppDestinationDefinition(
      destination: AppDestination.newAlert,
      path: '/alerts/new',
      titleRo: 'Alertă nouă',
      titleEn: 'New alert',
      icon: Icons.add_alert_rounded,
    ),
    AppDestination.editAlert: AppDestinationDefinition(
      destination: AppDestination.editAlert,
      path: '/alerts/:alertId/edit',
      titleRo: 'Editează alerta',
      titleEn: 'Edit alert',
      icon: Icons.edit_notifications_rounded,
      requiresEntity: true,
    ),
    AppDestination.toolkit: AppDestinationDefinition(
      destination: AppDestination.toolkit,
      path: '/toolkit',
      titleRo: 'Instrumente pescar',
      titleEn: 'Fisher toolkit',
      icon: Icons.handyman_rounded,
    ),
    AppDestination.permit: AppDestinationDefinition(
      destination: AppDestination.permit,
      path: '/permit',
      titleRo: 'Permise și sezoane',
      titleEn: 'Permits & seasons',
      icon: Icons.badge_rounded,
    ),
    AppDestination.regulations: AppDestinationDefinition(
      destination: AppDestination.regulations,
      path: '/regulations',
      titleRo: 'Reguli și dimensiuni',
      titleEn: 'Regulations & sizes',
      icon: Icons.rule_rounded,
    ),
    AppDestination.safety: AppDestinationDefinition(
      destination: AppDestination.safety,
      path: '/safety',
      titleRo: 'Siguranță',
      titleEn: 'Safety',
      icon: Icons.health_and_safety_rounded,
    ),
    AppDestination.profile: AppDestinationDefinition(
      destination: AppDestination.profile,
      path: '/profile',
      titleRo: 'Profil',
      titleEn: 'Profile',
      icon: Icons.person_rounded,
    ),
    AppDestination.accountSecurity: AppDestinationDefinition(
      destination: AppDestination.accountSecurity,
      path: '/account/security',
      titleRo: 'Cont și securitate',
      titleEn: 'Account & security',
      icon: Icons.security_rounded,
    ),
    AppDestination.recovery: AppDestinationDefinition(
      destination: AppDestination.recovery,
      path: '/account/recovery',
      titleRo: 'Recuperare cont',
      titleEn: 'Account recovery',
      icon: Icons.lock_reset_rounded,
    ),
    AppDestination.premium: AppDestinationDefinition(
      destination: AppDestination.premium,
      path: '/premium',
      titleRo: 'FluviAI Premium',
      titleEn: 'FluviAI Premium',
      icon: Icons.workspace_premium_rounded,
    ),
    AppDestination.restore: AppDestinationDefinition(
      destination: AppDestination.restore,
      path: '/premium/restore',
      titleRo: 'Restaurare achiziții',
      titleEn: 'Restore purchases',
      icon: Icons.restore_rounded,
    ),
    AppDestination.premiumRestored: AppDestinationDefinition(
      destination: AppDestination.premiumRestored,
      path: '/premium/restored',
      titleRo: 'Rezultat restaurare',
      titleEn: 'Restore result',
      icon: Icons.verified_user_rounded,
    ),
    AppDestination.support: AppDestinationDefinition(
      destination: AppDestination.support,
      path: '/support',
      titleRo: 'Ajutor și contact',
      titleEn: 'Help & contact',
      icon: Icons.support_agent_rounded,
    ),
    AppDestination.privacy: AppDestinationDefinition(
      destination: AppDestination.privacy,
      path: '/legal/confidentialitate',
      titleRo: 'Confidențialitate',
      titleEn: 'Privacy',
      icon: Icons.privacy_tip_rounded,
    ),
    AppDestination.terms: AppDestinationDefinition(
      destination: AppDestination.terms,
      path: '/legal/terms',
      titleRo: 'Termeni',
      titleEn: 'Terms',
      icon: Icons.gavel_rounded,
    ),
    AppDestination.licences: AppDestinationDefinition(
      destination: AppDestination.licences,
      path: '/legal/licences',
      titleRo: 'Licențe',
      titleEn: 'Licences',
      icon: Icons.code_rounded,
    ),
    AppDestination.about: AppDestinationDefinition(
      destination: AppDestination.about,
      path: '/about',
      titleRo: 'Despre FluviAI',
      titleEn: 'About FluviAI',
      icon: Icons.info_rounded,
    ),
    AppDestination.moderation: AppDestinationDefinition(
      destination: AppDestination.moderation,
      path: '/legal/moderation',
      titleRo: 'Comunitate și moderare',
      titleEn: 'Community and moderation',
      icon: Icons.policy_outlined,
    ),
    AppDestination.aiTransparency: AppDestinationDefinition(
      destination: AppDestination.aiTransparency,
      path: '/legal/ai-transparency',
      titleRo: 'Transparență AI',
      titleEn: 'AI transparency',
      icon: Icons.auto_awesome_outlined,
    ),
    AppDestination.legal: AppDestinationDefinition(
      destination: AppDestination.legal,
      path: '/legal',
      titleRo: 'Centru legal',
      titleEn: 'Legal hub',
      icon: Icons.account_balance_rounded,
    ),
    AppDestination.settings: AppDestinationDefinition(
      destination: AppDestination.settings,
      path: '/settings',
      titleRo: 'Setări',
      titleEn: 'Settings',
      icon: Icons.settings_rounded,
    ),
  };

  static AppDestinationDefinition of(AppDestination destination) =>
      definitions[destination]!;

  static AppDestinationDefinition? fromPath(String path) {
    final ordered = definitions.values.toList(growable: false)
      ..sort((left, right) {
        final leftDynamic = left.path.contains(':');
        final rightDynamic = right.path.contains(':');
        if (leftDynamic == rightDynamic) return 0;
        return leftDynamic ? 1 : -1;
      });
    for (final definition in ordered) {
      final pattern = RegExp(
        '^${definition.path.replaceAll(RegExp(r':[A-Za-z]+'), r'[^/]+')}\$',
      );
      if (pattern.hasMatch(path)) return definition;
    }
    return null;
  }
}
