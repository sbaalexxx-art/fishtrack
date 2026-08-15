import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/cache/timed_cache.dart';
import '../core/map/map_feature_registry.dart';
import '../l10n/l10n.dart';
import '../services/community_service.dart';
import '../widgets/loading_list_skeleton.dart';
import '../widgets/trust_badge.dart';
import 'add_catch_page.dart';
import 'community_details_page.dart';
import 'reports_archive_page.dart';
import 'report_detail_page.dart';

typedef CommunityFeedLoader =
    Future<CacheResult<List<CommunityPost>>> Function({
      required bool forceRefresh,
    });

String _compactCreateReportLabel(BuildContext context) {
  final fullLabel = context.l10n.createReport.trim();
  final lastSeparator = fullLabel.lastIndexOf(' ');
  final compactLabel = lastSeparator < 0
      ? fullLabel
      : fullLabel.substring(lastSeparator + 1);
  if (compactLabel.isEmpty) return fullLabel;
  return '${compactLabel[0].toUpperCase()}${compactLabel.substring(1)}';
}

String _compactAddCatchLabel(BuildContext context) {
  final fullLabel = context.l10n.addCatch.trim();
  final lastSeparator = fullLabel.lastIndexOf(' ');
  final compactLabel = lastSeparator < 0
      ? fullLabel
      : fullLabel.substring(lastSeparator + 1);
  if (compactLabel.isEmpty) return fullLabel;
  return '${compactLabel[0].toUpperCase()}${compactLabel.substring(1)}';
}

String _communityErrorMessage(
  BuildContext context,
  CommunityException error,
) => switch (error.code) {
  CommunityErrorCode.sessionExpired => context.l10n.sessionExpired,
  CommunityErrorCode.noInternet => context.l10n.noInternetConnection,
  CommunityErrorCode.requestTimedOut => context.l10n.requestTimedOut,
  CommunityErrorCode.reportPhotoPreparationFailed =>
    context.l10n.reportPhotoPreparationFailed,
  CommunityErrorCode.reportPhotoUploadFailed =>
    context.l10n.reportPhotoUploadFailed,
  CommunityErrorCode.reportPublishFailed => context.l10n.reportPublishFailed,
  CommunityErrorCode.reportVerificationFailed =>
    context.l10n.reportVerificationFailed,
  CommunityErrorCode.reportAbuseFailed => context.l10n.reportAbuseFailed,
  CommunityErrorCode.reportAlreadySubmitted =>
    context.l10n.reportAlreadySubmitted,
  CommunityErrorCode.communityUnavailable => context.l10n.communityUnavailable,
  _ => context.l10n.communityUnavailable,
};

class ReportsPageController extends ChangeNotifier {
  ReportCategory? _pendingInitialCategory;

  void requestCreateReport({required ReportCategory initialCategory}) {
    _pendingInitialCategory = initialCategory;
    notifyListeners();
  }

  ReportCategory? takePendingInitialCategory() {
    final category = _pendingInitialCategory;
    _pendingInitialCategory = null;
    return category;
  }
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({
    super.key,
    this.controller,
    this.feedLoader,
    this.onNavigate,
  });

  final ReportsPageController? controller;
  final CommunityFeedLoader? feedLoader;
  final ValueChanged<int>? onNavigate;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _service = const CommunityService();
  late Future<CacheResult<List<CommunityPost>>> _feed;
  CommunityPostType _selectedType = CommunityPostType.report;
  bool _fallbackMessageShown = false;
  bool _createReportDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _feed = _loadFeed(forceRefresh: true);
    widget.controller?.addListener(_handleCreateReportRequest);
  }

  @override
  void didUpdateWidget(covariant ReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?.removeListener(_handleCreateReportRequest);
    widget.controller?.addListener(_handleCreateReportRequest);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleCreateReportRequest);
    super.dispose();
  }

  Future<CacheResult<List<CommunityPost>>> _loadFeed({
    required bool forceRefresh,
  }) {
    final feedLoader = widget.feedLoader;
    return feedLoader != null
        ? feedLoader(forceRefresh: forceRefresh)
        : _service.getFeedResult(forceRefresh: forceRefresh);
  }

  Future<void> _refresh() async {
    final posts = await _loadFeed(forceRefresh: true);
    if (!mounted) return;
    setState(() {
      _feed = Future.value(posts);
    });
  }

  void _handleCreateReportRequest() {
    final initialCategory = widget.controller?.takePendingInitialCategory();
    if (initialCategory == null || !mounted) return;
    if (_selectedType != CommunityPostType.report) {
      setState(() => _selectedType = CommunityPostType.report);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _openCreateReportDialog(initialCategory: initialCategory);
      }
    });
  }

  Future<void> _openCreateReportDialog({
    ReportCategory initialCategory = ReportCategory.fishActivity,
  }) async {
    if (_createReportDialogOpen) return;
    _createReportDialogOpen = true;
    String? insertedReportId;
    try {
      insertedReportId = await showDialog<String>(
        context: context,
        builder: (_) => _CreateReportDialog(
          service: _service,
          initialCategory: initialCategory,
        ),
      );
    } finally {
      _createReportDialogOpen = false;
    }
    if (insertedReportId != null) {
      await _refresh();
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/me/reports'),
          builder: (_) => const ReportsArchivePage(),
        ),
      );
    }
  }

  Future<void> _openAddCatchPage() async {
    final catchAdded = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const AddCatchPage()));
    if (catchAdded == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isCatchesSelected = _selectedType == CommunityPostType.catchPost;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final mediaQuery = MediaQuery.of(context);
    final usableWidth =
        mediaQuery.size.width - mediaQuery.viewPadding.horizontal;
    final showActionLabel = !isLandscape || usableWidth >= 680;
    return Scaffold(
      appBar: AppBar(
        key: const Key('community-app-bar'),
        toolbarHeight: isLandscape ? 48 : null,
        centerTitle: isLandscape ? false : null,
        titleSpacing: isLandscape ? 8 : null,
        title: isLandscape
            ? Semantics(
                key: const Key('community-landscape-title-semantics'),
                container: true,
                explicitChildNodes: true,
                label: context.l10n.community,
                child: _CommunityFeedSelector(
                  selectedType: _selectedType,
                  onSelected: (type) => setState(() => _selectedType = type),
                  compact: true,
                ),
              )
            : Text(context.l10n.community),
        actions: [
          IconButton(
            key: const Key('community-archive-action'),
            tooltip: Localizations.localeOf(context).languageCode == 'ro'
                ? 'Rapoartele mele'
                : 'My reports',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: '/me/reports'),
                builder: (_) => const ReportsArchivePage(),
              ),
            ),
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          if (isCatchesSelected)
            _PremiumCommunityAction(
              actionKey: const Key('community-catch-appbar-action'),
              surfaceKey: const Key('community-catch-appbar-action-surface'),
              tooltip: context.l10n.addCatch,
              onPressed: _openAddCatchPage,
              icon: Icons.photo_camera_rounded,
              label: _compactAddCatchLabel(context),
              showLabel: showActionLabel,
            )
          else
            _PremiumCommunityAction(
              actionKey: const Key('community-report-appbar-action'),
              surfaceKey: const Key('community-report-appbar-action-surface'),
              tooltip: context.l10n.createReport,
              onPressed: _openCreateReportDialog,
              icon: Icons.add_rounded,
              label: _compactCreateReportLabel(context),
              showLabel: showActionLabel,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!isLandscape)
              _CommunityFeedSelector(
                selectedType: _selectedType,
                onSelected: (type) => setState(() => _selectedType = type),
              ),
            Expanded(
              child: FutureBuilder<CacheResult<List<CommunityPost>>>(
                future: _feed,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LoadingListSkeleton();
                  }
                  if (snapshot.hasError) {
                    return _FeedMessage(
                      icon: Icons.cloud_off_outlined,
                      message: snapshot.error is CommunityException
                          ? _communityErrorMessage(
                              context,
                              snapshot.error! as CommunityException,
                            )
                          : context.l10n.communityUnavailable,
                      action: _refresh,
                    );
                  }
                  final result = snapshot.data!;
                  if (result.isStaleFallback && !_fallbackMessageShown) {
                    _fallbackMessageShown = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.l10n.cachedDataFallback),
                          ),
                        );
                      }
                    });
                  }
                  final posts = result.value
                      .where((post) => post.type == _selectedType)
                      .toList(growable: false);
                  if (posts.isEmpty) {
                    return _FeedMessage(
                      icon: isCatchesSelected
                          ? Icons.set_meal_outlined
                          : Icons.campaign_outlined,
                      message: isCatchesSelected
                          ? context.l10n.noCatchesYet
                          : context.l10n.noReports,
                      action: _refresh,
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.separated(
                      key: const Key('community-feed-list'),
                      padding: EdgeInsets.fromLTRB(
                        isLandscape ? 8 : 12,
                        isLandscape ? 0 : 8,
                        isLandscape ? 8 : 12,
                        16 + MediaQuery.viewPaddingOf(context).bottom,
                      ),
                      itemCount: posts.length,
                      separatorBuilder: (_, _) =>
                          SizedBox(height: isLandscape ? 4 : 8),
                      itemBuilder: (context, index) => _CommunityPostCard(
                        post: posts[index],
                        onChanged: _refresh,
                        onNavigate: widget.onNavigate,
                      ),
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

class _PremiumCommunityAction extends StatelessWidget {
  const _PremiumCommunityAction({
    required this.actionKey,
    required this.surfaceKey,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.showLabel,
  });

  final Key actionKey;
  final Key surfaceKey;
  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            key: actionKey,
            height: 48,
            child: Center(
              child: Material(
                key: surfaceKey,
                color: colorScheme.primary,
                elevation: 1,
                shadowColor: colorScheme.shadow.withValues(alpha: .18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: colorScheme.onPrimary.withValues(alpha: .22),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  child: SizedBox(
                    height: 40,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: showLabel ? 12 : 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 19, color: colorScheme.onPrimary),
                          if (showLabel) ...[
                            const SizedBox(width: 7),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colorScheme.onPrimary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .1,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityFeedSelector extends StatelessWidget {
  const _CommunityFeedSelector({
    required this.selectedType,
    required this.onSelected,
    this.compact = false,
  });

  final CommunityPostType selectedType;
  final ValueChanged<CommunityPostType> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('community-feed-selector'),
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: colorScheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: .82),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: _CommunityFeedOption(
                label: context.l10n.catches,
                icon: Icons.set_meal_outlined,
                selectedIcon: Icons.set_meal_rounded,
                selected: selectedType == CommunityPostType.catchPost,
                onTap: () => onSelected(CommunityPostType.catchPost),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _CommunityFeedOption(
                label: context.l10n.reports,
                icon: Icons.campaign_outlined,
                selectedIcon: Icons.campaign_rounded,
                selected: selectedType == CommunityPostType.report,
                onTap: () => onSelected(CommunityPostType.report),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityFeedOption extends StatelessWidget {
  const _CommunityFeedOption({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 48,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(13),
        ),
        foregroundDecoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: BorderSide(
              width: selected ? 1.4 : 1,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: .62),
            ),
          ),
        ),
        child: Material(
          color: colorScheme.surface.withValues(alpha: 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: selected ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? selectedIcon : icon,
                    size: 20,
                    color: selected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: selected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        letterSpacing: selected ? .1 : 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityPostCard extends StatelessWidget {
  const _CommunityPostCard({
    required this.post,
    required this.onChanged,
    this.onNavigate,
  });

  final CommunityPost post;
  final VoidCallback onChanged;
  final ValueChanged<int>? onNavigate;

  Future<void> _open(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          name: post.type == CommunityPostType.catchPost
              ? '/catches/${post.id}'
              : '/reports/${post.id}',
        ),
        builder: (_) => post.type == CommunityPostType.catchPost
            ? CatchDetailsPage(post: post)
            : ReportDetailPage(
                post: post,
                onChanged: onChanged,
                onOpenMap: onNavigate == null
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        onNavigate!(1);
                      },
                onOpenFavorites: onNavigate == null
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        onNavigate!(3);
                      },
              ),
      ),
    );
    onChanged();
  }

  Future<void> _reportAbuse(BuildContext context) async {
    final reason = await showDialog<ReportAbuseReason>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.reportAbuse),
        children: [
          for (final reason in ReportAbuseReason.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, reason),
              child: Text(_abuseReasonLabel(context, reason)),
            ),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;
    try {
      await const CommunityService().reportAbuse(post.id, reason);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.reportSubmitted)));
      }
    } on CommunityException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_communityErrorMessage(context, error))),
        );
      }
    }
  }

  Future<void> _verify(
    BuildContext context,
    ReportVerification verification,
  ) async {
    try {
      await const CommunityService().verifyReport(post.id, verification);
      onChanged();
    } on CommunityException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_communityErrorMessage(context, error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (post.type == CommunityPostType.catchPost) {
      return _buildCatchCard(context);
    }
    return _buildReportCard(context);
  }

  Widget _buildCatchCard(BuildContext context) {
    if (MediaQuery.orientationOf(context) == Orientation.landscape) {
      return _buildLandscapeCatchCard(context);
    }
    final measurements = <String>[
      if (post.weight != null) '${post.weight!.toStringAsFixed(1)} kg',
      if (post.length != null) '${post.length!.toStringAsFixed(0)} cm',
    ].join(' \u2022 ');

    return Card(
      key: ValueKey('catch-card-${post.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundImage: post.authorAvatar?.isNotEmpty == true
                    ? NetworkImage(post.authorAvatar!)
                    : null,
                child: post.authorAvatar?.isNotEmpty == true
                    ? null
                    : const Icon(Icons.person_rounded),
              ),
              title: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    post.authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              subtitle: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(_relativeTime(context, post.createdAt)),
                  if (post.isSuspicious) const _UnderReviewBadge(),
                ],
              ),
              trailing: const Icon(Icons.set_meal_outlined),
            ),
            if (post.imageUrl case final String imageUrl)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: const Center(
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                post.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (post.body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  post.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _open(context),
                    icon: Icon(
                      post.isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                    ),
                  ),
                  Text('${post.likeCount}'),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _open(context),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                  ),
                  if (measurements.isEmpty)
                    const Spacer()
                  else
                    Expanded(
                      child: Text(
                        measurements,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeCatchCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final body = post.body.trim();

    return Card(
      key: ValueKey('catch-card-${post.id}'),
      margin: EdgeInsets.zero,
      elevation: 1,
      color: colorScheme.surfaceContainerLow,
      shadowColor: colorScheme.shadow.withValues(alpha: .12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => _open(context),
        child: SizedBox(
          height: 132,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: ValueKey('catch-card-thumbnail-${post.id}'),
                width: 112,
                child: switch (post.imageUrl) {
                  final String imageUrl => Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  _ => ColoredBox(
                    color: colorScheme.primaryContainer,
                    child: Icon(
                      Icons.set_meal_rounded,
                      size: 32,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                },
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 32,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: colorScheme.primaryContainer,
                              backgroundImage:
                                  post.authorAvatar?.isNotEmpty == true
                                  ? NetworkImage(post.authorAvatar!)
                                  : null,
                              child: post.authorAvatar?.isNotEmpty == true
                                  ? null
                                  : Icon(
                                      Icons.person_rounded,
                                      size: 16,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                post.authorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _relativeTime(context, post.createdAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (post.isSuspicious) ...[
                              const SizedBox(width: 6),
                              const Flexible(child: _UnderReviewBadge()),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        post.title,
                        key: ValueKey('catch-card-title-${post.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.1,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Row(
                        children: [
                          if (post.weight != null)
                            _CatchCardMetric(
                              icon: Icons.scale_outlined,
                              label: '${post.weight!.toStringAsFixed(1)} kg',
                            ),
                          if (post.weight != null && post.length != null)
                            const SizedBox(width: 10),
                          if (post.length != null)
                            _CatchCardMetric(
                              icon: Icons.straighten_rounded,
                              label: '${post.length!.toStringAsFixed(0)} cm',
                            ),
                          const Spacer(),
                          _CatchCardMetric(
                            icon: post.isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            label: '${post.likeCount}',
                            emphasized: post.isLiked,
                          ),
                          const SizedBox(width: 10),
                          const _CatchCardMetric(
                            icon: Icons.chat_bubble_outline_rounded,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final category = post.reportCategory;
    final categoryPresentation = category == null
        ? null
        : MapFeatureRegistry.forReportCategory(category, context.l10n);
    final title = post.title.trim();
    final titleMatchesCategory =
        category != null &&
        (title.toLowerCase() == category.name.toLowerCase() ||
            title.toLowerCase() == category.label.toLowerCase() ||
            title.toLowerCase() == categoryPresentation!.label.toLowerCase());
    final showTitle = title.isNotEmpty && !titleMatchesCategory;
    final hasLocation = post.latitude != null && post.longitude != null;

    if (MediaQuery.orientationOf(context) == Orientation.landscape) {
      return _buildLandscapeReportCard(
        context,
        categoryPresentation: categoryPresentation,
        title: title,
        showTitle: showTitle,
        hasLocation: hasLocation,
      );
    }

    return Card(
      key: ValueKey('report-card-${post.id}'),
      margin: EdgeInsets.zero,
      elevation: 1,
      color: colorScheme.surfaceContainerLow,
      shadowColor: colorScheme.shadow.withValues(alpha: .12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: colorScheme.primaryContainer,
                    backgroundImage: post.authorAvatar?.isNotEmpty == true
                        ? NetworkImage(post.authorAvatar!)
                        : null,
                    child: post.authorAvatar?.isNotEmpty == true
                        ? null
                        : Icon(
                            Icons.person_rounded,
                            size: 18,
                            color: colorScheme.onPrimaryContainer,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                post.authorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _relativeTime(context, post.createdAt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            TrustBadge(level: post.authorTrustLevel),
                            if (post.isSuspicious) ...[
                              const SizedBox(width: 4),
                              const Flexible(child: _UnderReviewBadge()),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  _buildReportOverflowMenu(context),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (categoryPresentation != null)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _ReportCategoryBadge(
                            icon: categoryPresentation.icon,
                            color: categoryPresentation.color,
                            label: categoryPresentation.label,
                          ),
                        ),
                      ),
                    if (categoryPresentation != null && hasLocation)
                      const SizedBox(width: 8),
                    if (hasLocation) const _ReportLocation(),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showTitle) ...[
                            const SizedBox(height: 4),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                            ),
                          ],
                          if (post.body.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              post.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (post.imageUrl case final String imageUrl) ...[
                      const SizedBox(width: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox.square(
                          dimension: 56,
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: colorScheme.surfaceContainerHighest,
                              child: const Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                _ReportVerificationActions(
                  stillValidCount: post.stillValidCount,
                  noLongerValidCount: post.noLongerValidCount,
                  onConfirm: () =>
                      _verify(context, ReportVerification.stillValid),
                  onNotAccurate: () =>
                      _verify(context, ReportVerification.noLongerValid),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeReportCard(
    BuildContext context, {
    required MapFeaturePresentation? categoryPresentation,
    required String title,
    required bool showTitle,
    required bool hasLocation,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final body = post.body.trim();

    return Card(
      key: ValueKey('report-card-${post.id}'),
      margin: EdgeInsets.zero,
      elevation: 1,
      color: colorScheme.surfaceContainerLow,
      shadowColor: colorScheme.shadow.withValues(alpha: .12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final proportionalActionsWidth = constraints.maxWidth * .48;
          final actionsWidth = proportionalActionsWidth > 360
              ? 360.0
              : proportionalActionsWidth;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: colorScheme.primaryContainer,
                        backgroundImage: post.authorAvatar?.isNotEmpty == true
                            ? NetworkImage(post.authorAvatar!)
                            : null,
                        child: post.authorAvatar?.isNotEmpty == true
                            ? null
                            : Icon(
                                Icons.person_rounded,
                                size: 18,
                                color: colorScheme.onPrimaryContainer,
                              ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        flex: 2,
                        child: Text(
                          post.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _relativeTime(context, post.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TrustBadge(level: post.authorTrustLevel),
                      if (post.isSuspicious) ...[
                        const SizedBox(width: 4),
                        const Flexible(child: _UnderReviewBadge()),
                      ],
                      if (categoryPresentation != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _ReportCategoryBadge(
                              icon: categoryPresentation.icon,
                              color: categoryPresentation.color,
                              label: categoryPresentation.label,
                            ),
                          ),
                        ),
                      ],
                      if (hasLocation) ...[
                        const SizedBox(width: 6),
                        const _ReportLocation(),
                      ],
                      _buildReportOverflowMenu(context),
                    ],
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (post.imageUrl case final String imageUrl) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox.square(
                            dimension: 44,
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => ColoredBox(
                                color: colorScheme.surfaceContainerHighest,
                                child: const Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (showTitle)
                                  TextSpan(
                                    text: title,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                if (showTitle && body.isNotEmpty)
                                  const TextSpan(text: ' — '),
                                if (body.isNotEmpty) TextSpan(text: body),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: actionsWidth,
                        child: _ReportVerificationActions(
                          stillValidCount: post.stillValidCount,
                          noLongerValidCount: post.noLongerValidCount,
                          onConfirm: () =>
                              _verify(context, ReportVerification.stillValid),
                          onNotAccurate: () => _verify(
                            context,
                            ReportVerification.noLongerValid,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildReportOverflowMenu(BuildContext context) =>
      PopupMenuButton<_ReportCardAction>(
        key: const Key('report-overflow-action'),
        tooltip: context.l10n.reportAbuse,
        icon: const Icon(Icons.more_horiz_rounded),
        onSelected: (_) => _reportAbuse(context),
        itemBuilder: (context) => [
          PopupMenuItem<_ReportCardAction>(
            value: _ReportCardAction.reportAbuse,
            child: Row(
              children: [
                const Icon(Icons.flag_outlined),
                const SizedBox(width: 8),
                Flexible(child: Text(context.l10n.reportAbuse)),
              ],
            ),
          ),
        ],
      );

  static String _relativeTime(BuildContext context, DateTime date) {
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return context.l10n.justNow;
    if (difference.inHours < 1) {
      return context.l10n.minutesAgo(difference.inMinutes);
    }
    if (difference.inDays < 1) {
      return context.l10n.hoursAgo(difference.inHours);
    }
    return context.l10n.daysAgo(difference.inDays);
  }
}

class _CatchCardMetric extends StatelessWidget {
  const _CatchCardMetric({
    required this.icon,
    this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String? label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = emphasized
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return Semantics(
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          if (label case final String value) ...[
            const SizedBox(width: 4),
            Text(
              value,
              maxLines: 1,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _ReportCardAction { reportAbuse }

class _ReportCategoryBadge extends StatelessWidget {
  const _ReportCategoryBadge({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .35)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ReportLocation extends StatelessWidget {
  const _ReportLocation();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: context.l10n.approximateLocation,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_on_outlined,
            size: 16,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 164),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n.approximateLocation,
                maxLines: 1,
                softWrap: false,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportVerificationActions extends StatelessWidget {
  const _ReportVerificationActions({
    required this.stillValidCount,
    required this.noLongerValidCount,
    required this.onConfirm,
    required this.onNotAccurate,
  });

  final int stillValidCount;
  final int noLongerValidCount;
  final VoidCallback onConfirm;
  final VoidCallback onNotAccurate;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _ReportVerificationButton(
          key: const Key('report-confirm-action'),
          icon: Icons.check_circle_outline_rounded,
          label: context.l10n.confirm,
          count: stillValidCount,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          onTap: onConfirm,
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: _ReportVerificationButton(
          key: const Key('report-not-accurate-action'),
          icon: Icons.warning_amber_rounded,
          label: context.l10n.notAccurate,
          count: noLongerValidCount,
          backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onTertiaryContainer,
          onTap: onNotAccurate,
        ),
      ),
    ],
  );
}

class _ReportVerificationButton extends StatelessWidget {
  const _ReportVerificationButton({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$label $count',
    excludeSemantics: true,
    child: SizedBox(
      height: 48,
      child: Material(
        color: backgroundColor.withValues(alpha: 0),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Center(
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: foregroundColor.withValues(alpha: .22),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: foregroundColor),
                  const SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: foregroundColor,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: foregroundColor.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _UnderReviewBadge extends StatelessWidget {
  const _UnderReviewBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      context.l10n.underReview,
      style: Theme.of(context).textTheme.labelSmall,
    ),
  );
}

class _CreateReportDialog extends StatefulWidget {
  const _CreateReportDialog({
    required this.service,
    required this.initialCategory,
  });

  final CommunityService service;
  final ReportCategory initialCategory;

  @override
  State<_CreateReportDialog> createState() => _CreateReportDialogState();
}

class _CreateReportDialogState extends State<_CreateReportDialog> {
  final _descriptionController = TextEditingController();
  late ReportCategory _category;
  File? _cameraPhoto;
  bool _useExactLocation = true;
  bool _trustConfirmed = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final insertedReportId = await widget.service.createReport(
        category: _category,
        text: _descriptionController.text,
        cameraPhoto: _cameraPhoto,
        useExactLocation: _useExactLocation,
      );
      if (mounted) Navigator.of(context).pop(insertedReportId);
    } on CommunityException catch (error) {
      if (mounted) {
        setState(() => _error = _communityErrorMessage(context, error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _takePhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (photo != null && mounted) {
      setState(() => _cameraPhoto = File(photo.path));
    }
  }

  Future<void> _openCategoryPicker() async {
    if (_saving) return;
    final colorScheme = Theme.of(context).colorScheme;
    final selected = await showModalBottomSheet<ReportCategory>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: colorScheme.surface,
      constraints: const BoxConstraints(maxWidth: 900),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      builder: (context) =>
          _ReportCategoryPickerSheet(selectedCategory: _category),
    );
    if (!mounted || selected == null) return;
    setState(() => _category = selected);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final photoPresentation = MapFeatureRegistry.forFeature(
      MapFeatureType.photo,
      context.l10n,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;
        final mediaSafeWidth =
            mediaQuery.size.width - mediaQuery.viewPadding.horizontal;
        final mediaSafeHeight =
            mediaQuery.size.height - mediaQuery.viewPadding.vertical;
        final safeWidth = availableWidth < mediaSafeWidth
            ? availableWidth
            : mediaSafeWidth;
        final safeHeight = availableHeight < mediaSafeHeight
            ? availableHeight
            : mediaSafeHeight;
        final usableHeight = safeHeight - mediaQuery.viewInsets.vertical;
        final compactLandscapeCandidate =
            mediaQuery.orientation == Orientation.landscape &&
            mediaQuery.viewInsets.bottom == 0 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.3 &&
            safeWidth >= 700 &&
            usableHeight >= 350;
        final horizontalInset = compactLandscapeCandidate
            ? (safeWidth < 800 ? 8.0 : 10.0)
            : safeWidth < 360
            ? 12.0
            : safeWidth < 420
            ? 16.0
            : safeWidth < 600
            ? 20.0
            : 32.0;
        final verticalInset = compactLandscapeCandidate
            ? 4.0
            : safeHeight < 800
            ? 12.0
            : 24.0;
        final constrainedWidth = safeWidth - (horizontalInset * 2);
        final constrainedHeight = usableHeight - (verticalInset * 2);
        final useTwoColumns =
            compactLandscapeCandidate && constrainedWidth >= 680;
        final widthLimit = useTwoColumns ? 880.0 : 520.0;
        final maxWidth = constrainedWidth < widthLimit
            ? constrainedWidth
            : widthLimit;
        final maxHeight = constrainedHeight > 0
            ? constrainedHeight
            : safeHeight;
        final contentPadding = useTwoColumns
            ? 8.0
            : maxWidth < 360
            ? 12.0
            : 16.0;
        final body = SingleChildScrollView(
          padding: EdgeInsets.all(contentPadding),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: _buildForm(
            context,
            photoPresentation: photoPresentation,
            useTwoColumns: useTwoColumns,
            compactLandscape: useTwoColumns,
          ),
        );

        return Dialog(
          key: const ValueKey('add-report-dialog'),
          insetPadding: EdgeInsets.symmetric(
            horizontal: horizontalInset,
            vertical: verticalInset,
          ),
          clipBehavior: Clip.antiAlias,
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: useTwoColumns ? maxWidth : 0,
              maxWidth: maxWidth,
              minHeight: useTwoColumns ? maxHeight : 0,
              maxHeight: maxHeight,
            ),
            child: Column(
              mainAxisSize: useTwoColumns ? MainAxisSize.max : MainAxisSize.min,
              children: [
                SizedBox(
                  height: useTwoColumns ? 48 : null,
                  child: Padding(
                    padding: useTwoColumns
                        ? const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          )
                        : EdgeInsets.fromLTRB(
                            contentPadding,
                            12,
                            contentPadding,
                            8,
                          ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        context.l10n.createReport,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
                Divider(height: 1, color: colorScheme.outlineVariant),
                if (useTwoColumns)
                  Expanded(child: body)
                else
                  Flexible(child: body),
                Divider(height: 1, color: colorScheme.outlineVariant),
                SizedBox(
                  height: useTwoColumns ? 52 : null,
                  child: Padding(
                    padding: useTwoColumns
                        ? const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          )
                        : EdgeInsets.fromLTRB(
                            contentPadding,
                            8,
                            contentPadding,
                            8,
                          ),
                    child: OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: 8,
                      overflowSpacing: 4,
                      overflowAlignment: OverflowBarAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: Text(context.l10n.cancel),
                        ),
                        FilledButton(
                          onPressed: _saving || !_trustConfirmed ? null : _save,
                          child: Text(
                            _saving
                                ? context.l10n.publishing
                                : context.l10n.publish,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildForm(
    BuildContext context, {
    required MapFeaturePresentation photoPresentation,
    required bool useTwoColumns,
    required bool compactLandscape,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelGap = compactLandscape ? 2.0 : 4.0;
    final sectionGap = compactLandscape ? 4.0 : 8.0;
    final primaryFields = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormLabel(context.l10n.reportCategory),
        SizedBox(height: labelGap),
        _buildCategorySelector(context, compactLandscape: compactLandscape),
        SizedBox(height: sectionGap),
        _FormLabel(context.l10n.descriptionOptional),
        SizedBox(height: labelGap),
        TextField(
          controller: _descriptionController,
          enabled: !_saving,
          minLines: 1,
          maxLines: 3,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: _compactInputDecoration(
            colorScheme,
            compactLandscape: compactLandscape,
          ),
        ),
        SizedBox(height: sectionGap),
        _buildPhotoSection(
          context,
          photoPresentation,
          compactLandscape: compactLandscape,
        ),
      ],
    );
    final secondaryFields = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLocationControl(context, compactLandscape: compactLandscape),
        SizedBox(height: compactLandscape ? 2 : 4),
        _buildTrustSection(context, compactLandscape: compactLandscape),
      ],
    );
    final fields = useTwoColumns
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: primaryFields),
              SizedBox(width: compactLandscape ? 12 : 16),
              Expanded(child: secondaryFields),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primaryFields,
              const SizedBox(height: 4),
              secondaryFields,
            ],
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fields,
        if (_error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategorySelector(
    BuildContext context, {
    required bool compactLandscape,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(12);

    return Semantics(
      button: true,
      enabled: !_saving,
      label: context.l10n.reportCategory,
      child: Opacity(
        opacity: _saving ? 0.6 : 1,
        child: Material(
          color: colorScheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _saving ? null : _openCategoryPicker,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compactLandscape ? 10 : 12,
                  vertical: compactLandscape ? 6 : 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _ReportCategoryOption(
                        category: _category,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoSection(
    BuildContext context,
    MapFeaturePresentation presentation, {
    required bool compactLandscape,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final information = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.reportPhotoOptional,
          style: theme.textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          context.l10n.reportPhotoOptionalHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        if (_cameraPhoto != null) ...[
          SizedBox(height: compactLandscape ? 4 : 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.l10n.reportPhotoReady,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
    final button = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: compactLandscape ? 8 : 10,
          vertical: compactLandscape ? 6 : 8,
        ),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: _saving ? null : _takePhoto,
      icon: Icon(presentation.icon, color: presentation.color),
      label: Text(
        _cameraPhoto == null
            ? context.l10n.takeLivePhoto
            : context.l10n.retakeLivePhoto,
        textAlign: TextAlign.center,
      ),
    );

    return Container(
      padding: EdgeInsets.all(compactLandscape ? 6 : 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useHorizontalLayout =
              constraints.maxWidth >= 328 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.3;
          if (!useHorizontalLayout) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                information,
                SizedBox(height: compactLandscape ? 4 : 6),
                Align(alignment: Alignment.centerLeft, child: button),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: information),
              SizedBox(width: compactLandscape ? 8 : 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: compactLandscape ? 150 : 160,
                ),
                child: button,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLocationControl(
    BuildContext context, {
    required bool compactLandscape,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    void updateValue(bool value) {
      if (!_saving) setState(() => _useExactLocation = value);
    }

    return Semantics(
      button: true,
      enabled: !_saving,
      toggled: _useExactLocation,
      label: context.l10n.useExactLocation,
      hint: context.l10n.approximateLocationHint,
      onTap: _saving ? null : () => updateValue(!_useExactLocation),
      excludeSemantics: true,
      child: Material(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _saving ? null : () => updateValue(!_useExactLocation),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 4,
                vertical: compactLandscape ? 2 : 4,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.useExactLocation,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          context.l10n.approximateLocationHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: compactLandscape ? 6 : 8),
                  Switch.adaptive(
                    value: _useExactLocation,
                    onChanged: _saving ? null : updateValue,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrustSection(
    BuildContext context, {
    required bool compactLandscape,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: EdgeInsets.all(compactLandscape ? 6 : 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 20,
                color: colorScheme.primary,
              ),
              SizedBox(width: compactLandscape ? 6 : 8),
              Expanded(
                child: Text(
                  context.l10n.communityTrustTitle,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compactLandscape ? 2 : 4),
          Text(
            context.l10n.communityTrustBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Semantics(
            button: true,
            enabled: !_saving,
            checked: _trustConfirmed,
            label: context.l10n.reportTruthConfirmation,
            onTap: _saving
                ? null
                : () => setState(() => _trustConfirmed = !_trustConfirmed),
            excludeSemantics: true,
            child: Material(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _saving
                    ? null
                    : () => setState(() => _trustConfirmed = !_trustConfirmed),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: compactLandscape ? 2 : 3),
                        child: Checkbox(
                          value: _trustConfirmed,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () => _trustConfirmed = value ?? false,
                                ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: compactLandscape ? 3 : 5,
                            right: 4,
                          ),
                          child: Text(
                            context.l10n.reportTruthConfirmation,
                            style:
                                (compactLandscape
                                        ? theme.textTheme.bodySmall
                                        : theme.textTheme.bodyMedium)
                                    ?.copyWith(color: colorScheme.onSurface),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            context.l10n.misleadingReportsWarning,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _compactInputDecoration(
    ColorScheme colorScheme, {
    required bool compactLandscape,
  }) => InputDecoration(
    isDense: true,
    filled: true,
    fillColor: colorScheme.surfaceContainer,
    contentPadding: EdgeInsets.symmetric(
      horizontal: compactLandscape ? 10 : 12,
      vertical: compactLandscape ? 6 : 8,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.primary, width: 2),
    ),
  );
}

class _ReportCategoryPickerSheet extends StatelessWidget {
  const _ReportCategoryPickerSheet({required this.selectedCategory});

  final ReportCategory selectedCategory;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : mediaQuery.size.height - mediaQuery.viewPadding.vertical;
        final availableHeight = viewportHeight - mediaQuery.viewInsets.vertical;
        final isLandscape = mediaQuery.orientation == Orientation.landscape;
        final hasLargeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final useTwoColumns =
            isLandscape &&
            !hasLargeText &&
            mediaQuery.viewInsets.bottom == 0 &&
            constraints.maxWidth >= 680;
        final widthLimit = useTwoColumns ? 840.0 : 560.0;
        final sheetWidth = constraints.maxWidth < widthLimit
            ? constraints.maxWidth
            : widthLimit;
        final heightFactor = isLandscape
            ? (hasLargeText ? 0.92 : 0.86)
            : (hasLargeText ? 0.76 : 0.68);
        final preferredHeight = availableHeight * heightFactor;
        final sheetHeight = preferredHeight < 640 ? preferredHeight : 640.0;
        final categoryList = useTwoColumns
            ? GridView.builder(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 56,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 4,
                ),
                itemCount: ReportCategory.values.length,
                itemBuilder: (context, index) =>
                    _buildCategoryItem(context, ReportCategory.values[index]),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                itemCount: ReportCategory.values.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) =>
                    _buildCategoryItem(context, ReportCategory.values[index]),
              );

        return SizedBox(
          width: sheetWidth,
          height: sheetHeight,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.l10n.reportCategory,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
              Expanded(child: categoryList),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryItem(BuildContext context, ReportCategory category) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = category == selectedCategory;
    final borderRadius = BorderRadius.circular(12);

    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: isSelected ? colorScheme.primaryContainer : colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(category),
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _ReportCategoryOption(
                      category: category,
                      compact: true,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.check_circle_rounded,
                      color: colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
}

class _ReportCategoryOption extends StatelessWidget {
  const _ReportCategoryOption({required this.category, this.compact = false});

  final ReportCategory category;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final presentation = MapFeatureRegistry.forReportCategory(
      category,
      context.l10n,
    );
    final iconSize = compact ? 18.0 : 20.0;

    return Row(
      children: [
        Container(
          width: compact ? 28 : 32,
          height: compact ? 28 : 32,
          decoration: BoxDecoration(
            color: presentation.color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(compact ? 8 : 10),
            border: Border.all(
              color: presentation.color.withValues(alpha: .32),
            ),
          ),
          child: Icon(
            presentation.icon,
            size: iconSize,
            color: presentation.color,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            presentation.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

String _abuseReasonLabel(BuildContext context, ReportAbuseReason reason) =>
    switch (reason) {
      ReportAbuseReason.spam => context.l10n.abuseReasonSpam,
      ReportAbuseReason.fakeInformation =>
        context.l10n.abuseReasonFakeInformation,
      ReportAbuseReason.offensiveContent =>
        context.l10n.abuseReasonOffensiveContent,
      ReportAbuseReason.dangerousIllegalActivity =>
        context.l10n.abuseReasonDangerousIllegalActivity,
      ReportAbuseReason.other => context.l10n.abuseReasonOther,
    };

class _FeedMessage extends StatelessWidget {
  const _FeedMessage({
    required this.icon,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final String message;
  final Future<void> Function() action;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: action,
    child: ListView(
      padding: EdgeInsets.only(
        bottom: 16 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 48),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: action,
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
