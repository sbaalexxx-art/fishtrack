import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/l10n.dart';
import '../core/navigation/app_destination.dart';
import '../core/navigation/app_navigator.dart';
import '../services/auth_service.dart';
import '../services/reputation_service.dart';
import '../widgets/trust_badge.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _authService = const AuthService();
  final _picker = ImagePicker();
  late final TextEditingController _nameController;
  bool _saving = false;
  String? _avatarUrl;
  bool _avatarLoadFailed = false;
  String? _error;
  late final Future<ReputationMetrics> _reputation;

  @override
  void initState() {
    super.initState();
    final metadata = _authService.currentUser?.userMetadata;
    _nameController = TextEditingController(
      text: metadata?['full_name']?.toString() ?? '',
    );
    _avatarUrl = metadata?['avatar_url']?.toString();
    _reputation = const ReputationService().getCurrentUserReputation();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _changeAvatar() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (image == null || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final url = await _authService.uploadAvatar(image.path);
      if (mounted) {
        setState(() {
          _avatarUrl = url;
          _avatarLoadFailed = false;
        });
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = context.l10n.nameRequired);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _authService.updateProfile(name: _nameController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.profileUpdated)));
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _authService.logout();
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final hasAvatar = (_avatarUrl?.isNotEmpty ?? false) && !_avatarLoadFailed;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.profile),
        actions: [
          IconButton(
            key: const Key('profile-premium-action'),
            tooltip: 'FluviAI Premium',
            onPressed: () => AppNavigator.open(context, AppDestination.premium),
            icon: const Icon(Icons.workspace_premium_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
          children: [
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 54,
                    backgroundImage: hasAvatar
                        ? NetworkImage(_avatarUrl!)
                        : null,
                    onBackgroundImageError: hasAvatar
                        ? (_, _) {
                            if (mounted && !_avatarLoadFailed) {
                              setState(() => _avatarLoadFailed = true);
                            }
                          }
                        : null,
                    child: hasAvatar
                        ? null
                        : const Icon(Icons.person_rounded, size: 54),
                  ),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: IconButton.filled(
                      onPressed: _saving ? null : _changeAvatar,
                      tooltip: context.l10n.changeAvatar,
                      icon: const Icon(Icons.photo_camera_outlined),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _nameController,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: context.l10n.name,
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: user?.email ?? '',
              readOnly: true,
              decoration: InputDecoration(
                labelText: context.l10n.email,
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<ReputationMetrics>(
              future: _reputation,
              builder: (context, snapshot) {
                final reputation = snapshot.data;
                if (reputation == null) return const SizedBox.shrink();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.verified_user_outlined),
                  title: Text(
                    context.l10n.reputationValue(reputation.reputationScore),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TrustBadge(level: reputation.trustLevel),
                );
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _saveProfile,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                _saving ? context.l10n.saving : context.l10n.saveProfile,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving ? null : _logout,
              icon: const Icon(Icons.logout_rounded),
              label: Text(context.l10n.logout),
            ),
          ],
        ),
      ),
    );
  }
}
