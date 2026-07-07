import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/community_service.dart';
import '../widgets/trust_badge.dart';

class CatchDetailsPage extends StatefulWidget {
  const CatchDetailsPage({super.key, required this.post});

  final CommunityPost post;

  @override
  State<CatchDetailsPage> createState() => _CatchDetailsPageState();
}

class _CatchDetailsPageState extends State<CatchDetailsPage> {
  final _service = const CommunityService();
  final _commentController = TextEditingController();
  late CommunityPost _post;
  late Future<List<CommunityComment>> _comments;
  bool _liking = false;
  bool _commenting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _comments = _service.getComments(_post.id);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    setState(() {
      _liking = true;
      _error = null;
    });
    try {
      final liked = await _service.toggleLike(_post);
      if (!mounted) return;
      setState(() {
        _post = _post.copyWith(
          isLiked: liked,
          likeCount: (_post.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 30),
        );
      });
    } on CommunityException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  Future<void> _addComment() async {
    final body = _commentController.text.trim();
    if (body.isEmpty) return;
    setState(() {
      _commenting = true;
      _error = null;
    });
    try {
      await _service.addComment(catchId: _post.id, body: body);
      _commentController.clear();
      if (!mounted) return;
      setState(() => _comments = _service.getComments(_post.id));
    } on CommunityException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _commenting = false);
    }
  }

  void _openProfile(String userId) {
    if (userId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityProfilePage(userId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.catchDetails)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            InkWell(
              onTap: () => _openProfile(_post.userId),
              child: Row(
                children: [
                  _Avatar(url: _post.authorAvatar),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _post.authorName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_post.imageUrl case final String imageUrl)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Colors.black12,
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(_post.title, style: Theme.of(context).textTheme.headlineSmall),
            if (_post.weight != null || _post.length != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (_post.weight != null)
                    '${_post.weight!.toStringAsFixed(1)} kg',
                  if (_post.length != null)
                    '${_post.length!.toStringAsFixed(0)} cm',
                ].join(' • '),
              ),
            ],
            if (_post.body.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_post.body),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _liking ? null : _toggleLike,
                icon: Icon(
                  _post.isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
                label: Text(context.l10n.likes(_post.likeCount)),
              ),
            ),
            const Divider(height: 28),
            Text(
              context.l10n.comments,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    enabled: !_commenting,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: context.l10n.addComment,
                    ),
                  ),
                ),
                IconButton.filled(
                  onPressed: _commenting ? null : _addComment,
                  icon: _commenting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            FutureBuilder<List<CommunityComment>>(
              future: _comments,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Text(context.l10n.commentsUnavailable);
                }
                final comments = snapshot.data ?? const [];
                if (comments.isEmpty) {
                  return Text(context.l10n.noComments);
                }
                return Column(
                  children: [
                    for (final comment in comments)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => _openProfile(comment.userId),
                        leading: _Avatar(url: comment.authorAvatar, radius: 18),
                        title: Text(comment.authorName),
                        subtitle: Text(comment.body),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CommunityProfilePage extends StatelessWidget {
  const CommunityProfilePage({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.anglerProfile)),
      body: SafeArea(
        child: FutureBuilder<CommunityProfile>(
          future: const CommunityService().getProfile(userId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return Center(child: Text(context.l10n.profileUnavailable));
            }
            final profile = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(child: _Avatar(url: profile.avatarUrl, radius: 52)),
                const SizedBox(height: 16),
                Text(
                  profile.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Center(child: TrustBadge(level: profile.trustLevel)),
                if (profile.country case final String country)
                  Text(country, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ProfileStat(
                      label: context.l10n.catches,
                      value: profile.catchCount,
                    ),
                    _ProfileStat(
                      label: context.l10n.reputation,
                      value: profile.reputation,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('$value', style: Theme.of(context).textTheme.headlineSmall),
      Text(label),
    ],
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.url, this.radius = 22});
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hasImage = url?.isNotEmpty ?? false;
    return CircleAvatar(
      radius: radius,
      backgroundImage: hasImage ? NetworkImage(url!) : null,
      child: hasImage ? null : const Icon(Icons.person_rounded),
    );
  }
}
