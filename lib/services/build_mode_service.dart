import 'package:flutter/foundation.dart';

abstract final class BuildModeService {
  static const bool isDebugBuild = kDebugMode;
  static const bool isReleaseBuild = kReleaseMode;
  static const bool isDeveloperVisible = isDebugBuild;

  static String get environment => isDebugBuild ? 'Debug' : 'Release';
}
