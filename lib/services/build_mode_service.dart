import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class BuildModeService {
  /// Explicitly enabled only for Product Owner / internal QA builds.
  static const bool isPoInternalBuild = bool.fromEnvironment(
    'FLUVIAI_PO_BUILD',
    defaultValue: false,
  );

  static const bool isDebugBuild = kDebugMode;
  static const bool isReleaseBuild = kReleaseMode;

  static bool _accountDeveloperEnabled = false;
  static bool _accountDiagnosticsEnabled = false;
  static String? _accountRole;
  static String? _resolvedUserId;

  /// Account-scoped internal access resolved from Supabase.
  ///
  /// This is intentionally runtime state. Public users remain fail-closed.
  static bool get isAccountDeveloper => _accountDeveloperEnabled;

  static bool get isProductOwner =>
      _accountDeveloperEnabled && _accountRole == 'product_owner';

  static bool get isInternalDiagnosticsEnabled =>
      isDebugBuild ||
      isPoInternalBuild ||
      (_accountDeveloperEnabled && _accountDiagnosticsEnabled);

  static String? get internalRole => _accountRole;

  static String? get resolvedUserId => _resolvedUserId;

  /// Developer tooling is visible for:
  /// - local debug builds;
  /// - explicit PO/internal builds;
  /// - authenticated accounts granted developer access server-side.
  static bool get isDeveloperVisible =>
      isDebugBuild || isPoInternalBuild || _accountDeveloperEnabled;

  /// Resolves only the currently authenticated user's internal access.
  ///
  /// The backend RPC uses auth.uid(), so another user's entitlement cannot
  /// be requested by supplying an arbitrary user id from the client.
  static Future<void> refreshInternalAccess() async {
    clearInternalAccess();

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    _resolvedUserId = user.id;

    try {
      final response = await client.rpc('get_my_internal_access_v1');

      if (response is! List || response.isEmpty || response.first is! Map) {
        return;
      }

      final row = Map<String, dynamic>.from(response.first as Map);

      final role = (row['role'] as String?)?.trim().toLowerCase();
      final developerEnabled = row['developer_mode_enabled'] == true;
      final diagnosticsEnabled = row['diagnostics_enabled'] == true;

      _accountRole = role;
      _accountDeveloperEnabled = developerEnabled;
      _accountDiagnosticsEnabled = diagnosticsEnabled;
    } on Object {
      // Fail closed. A backend/network error must never expose internal tools
      // to a public account.
      _accountRole = null;
      _accountDeveloperEnabled = false;
      _accountDiagnosticsEnabled = false;
    }
  }

  static void clearInternalAccess() {
    _accountRole = null;
    _accountDeveloperEnabled = false;
    _accountDiagnosticsEnabled = false;
    _resolvedUserId = null;
  }

  static String get environment {
    if (isProductOwner) {
      return isDebugBuild ? 'PO Account Debug' : 'PO Account';
    }
    if (isPoInternalBuild) {
      return isDebugBuild ? 'PO Debug' : 'PO Internal';
    }
    return isDebugBuild ? 'Debug' : 'Release';
  }
}
