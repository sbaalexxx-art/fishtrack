import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/community_service.dart';
import 'community_details_page.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _service = const CommunityService();
  late Future<List<CommunityPost>> _feed;

  @override
  void initState() {
    super.initState();
    _feed = _service.getFeed();
  }

  Future<void> _refresh() async {
    final posts = await _service.getFeed();
    if (mounted) setState(() => _feed = Future.value(posts));
  }

  Future<void> _openCreateReportDialog() async {
    final insertedReportId = await showDialog<String>(
      context: context,
      builder: (_) => _CreateReportDialog(service: _service),
    );
    if (insertedReportId != null) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Community')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateReportDialog,
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('Report'),
      ),
      body: SafeArea(
        child: FutureBuilder<List<CommunityPost>>(
          future: _feed,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _FeedMessage(
                icon: Icons.cloud_off_outlined,
                message: snapshot.error is CommunityException
                    ? (snapshot.error! as CommunityException).message
                    : 'Community feed is unavailable.',
                action: _refresh,
              );
            }
            final posts = snapshot.data ?? const [];
            if (posts.isEmpty) {
              return _FeedMessage(
                icon: Icons.groups_outlined,
                message: 'No community activity yet.',
                action: _refresh,
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                itemCount: posts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _CommunityPostCard(post: posts[index], onChanged: _refresh),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CommunityPostCard extends StatelessWidget {
  const _CommunityPostCard({required this.post, required this.onChanged});

  final CommunityPost post;
  final VoidCallback onChanged;

  Future<void> _open(BuildContext context) async {
    if (post.type != CommunityPostType.catchPost) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CatchDetailsPage(post: post)),
    );
    onChanged();
  }

  Future<void> _reportAbuse(BuildContext context) async {
    final reason = await showDialog<ReportAbuseReason>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Report Abuse'),
        children: [
          for (final reason in ReportAbuseReason.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, reason),
              child: Text(reason.label),
            ),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;
    try {
      await const CommunityService().reportAbuse(post.id, reason);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted for review.')),
        );
      }
    } on CommunityException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCatch = post.type == CommunityPostType.catchPost;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isCatch ? () => _open(context) : null,
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
              title: Text(post.authorName),
              subtitle: Text(_relativeTime(post.createdAt)),
              trailing: Icon(
                isCatch ? Icons.set_meal_outlined : Icons.campaign_outlined,
              ),
            ),
            if (post.imageUrl case final String imageUrl)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Colors.black12,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
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
                  if (isCatch) ...[
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
                    const Spacer(),
                    if (post.weight != null)
                      Text('${post.weight!.toStringAsFixed(1)} kg'),
                    if (post.length != null)
                      Text(' • ${post.length!.toStringAsFixed(0)} cm'),
                  ] else
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              await const CommunityService().verifyReport(
                                post.id,
                                ReportVerification.stillValid,
                              );
                              onChanged();
                            },
                            icon: const Icon(
                              Icons.check_circle_outline_rounded,
                            ),
                            label: Text('Confirm ${post.stillValidCount}'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await const CommunityService().verifyReport(
                                post.id,
                                ReportVerification.noLongerValid,
                              );
                              onChanged();
                            },
                            icon: const Icon(Icons.warning_amber_rounded),
                            label: Text(
                              'Not accurate ${post.noLongerValidCount}',
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _reportAbuse(context),
                            icon: const Icon(Icons.flag_outlined),
                            label: const Text('Report Abuse'),
                          ),
                        ],
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

  static String _relativeTime(DateTime date) {
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}

class _CreateReportDialog extends StatefulWidget {
  const _CreateReportDialog({required this.service});
  final CommunityService service;

  @override
  State<_CreateReportDialog> createState() => _CreateReportDialogState();
}

class _CreateReportDialogState extends State<_CreateReportDialog> {
  final _descriptionController = TextEditingController();
  ReportCategory _category = ReportCategory.fishActivity;
  File? _cameraPhoto;
  bool _useExactLocation = true;
  bool _trustConfirmed = false;
  bool _saving = false;
  String? _error;

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
      if (mounted) setState(() => _error = error.message);
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Report'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<ReportCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Report category'),
              items: ReportCategory.values
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category.label),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _category = value!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              enabled: !_saving,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving ? null : _takePhoto,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(
                _cameraPhoto == null ? 'Take live photo' : 'Retake live photo',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use exact location'),
              subtitle: const Text('Disable to share an approximate location'),
              value: _useExactLocation,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _useExactLocation = value),
            ),
            const Divider(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '🤝 Respectă pescarii. Respectă natura.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Comunitatea AIFishMap se bazează pe încredere.\n'
              'Publică doar informații reale și actuale pentru a-i ajuta pe '
              'ceilalți pescari să ia cele mai bune decizii pe apă.',
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _trustConfirmed,
              title: const Text(
                'Confirm că acest raport este real și reflectă condițiile '
                'din acest moment.',
              ),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _trustConfirmed = value ?? false),
            ),
            const Text(
              'False or misleading reports may be removed and can affect '
              'your Community Reputation.',
              style: TextStyle(fontSize: 12),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || !_trustConfirmed ? null : _save,
          child: Text(_saving ? 'Publishing…' : 'Publish'),
        ),
      ],
    );
  }
}

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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: action, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
