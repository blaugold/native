// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:glob/glob.dart';
import 'package:logging/logging.dart';
import 'package:native_assets_cli/native_assets_cli.dart';
import 'package:path/path.dart' as p;

import '../tool/tool_error.dart';
import 'run_meson_builder.dart';

class MesonBuilder {
  final String? assetId;
  final String project;
  final String target;
  final Map<String, String> options;
  final List<String> excludeFromDependencies;
  final List<String> dartBuildFiles;
  final LinkMode? linkMode;

  MesonBuilder.library({
    required this.assetId,
    required this.project,
    required this.target,
    this.options = const {},
    this.excludeFromDependencies = const [],
    this.dartBuildFiles = const ['build.dart'],
    this.linkMode,
  });

  Future<void> run({
    required BuildConfig buildConfig,
    required BuildOutput buildOutput,
    required Logger? logger,
  }) async {
    final packageRoot = buildConfig.packageRoot;
    final outDir = buildConfig.outDir;
    final projectDir = packageRoot.resolve(project);
    final projectDirPath = projectDir.toFilePath();

    final (path: targetPath, name: targetName) = _parseMesonTarget(target);

    final libUri = outDir
        .resolve(targetPath == null ? './' : '$targetPath/')
        .resolve(buildConfig.targetOs.mesonNinjaDylibFileName(targetName));

    final dartBuildFiles = [
      for (final source in this.dartBuildFiles) packageRoot.resolve(source),
    ];

    final linkModePreference = buildConfig.linkModePreference;
    final resolvedLinkMode = linkMode ?? linkModePreference.preferredLinkMode;
    final targetWithType = '$target:${resolvedLinkMode.mesonTargetType}';

    if (!linkModePreference.potentialLinkMode.contains(resolvedLinkMode)) {
      final errorMessage = 'Link mode $resolvedLinkMode is not supported.';
      logger?.severe(errorMessage);
      throw ToolError(errorMessage);
    }

    if (!buildConfig.dryRun) {
      final task = RunMesonBuilder(
        buildConfig: buildConfig,
        logger: logger,
        projectDir: projectDir,
        mesonTarget: targetWithType,
        options: {
          ...options,
          'buildtype':
              buildConfig.buildMode == BuildMode.release ? 'release' : 'debug',
          'default_library': resolvedLinkMode.libraryType,
        },
      );
      await task.run();
    }

    final targets = [
      if (!buildConfig.dryRun)
        buildConfig.target
      else
        for (final target in Target.values)
          if (target.os == buildConfig.targetOs) target
    ];
    for (final target in targets) {
      buildOutput.assets.add(Asset(
        id: assetId!,
        linkMode: resolvedLinkMode,
        target: target,
        path: AssetAbsolutePath(libUri),
      ));
    }

    if (!buildConfig.dryRun) {
      final excludeGlobs = excludeFromDependencies.map((pattern) =>
          Glob(pattern, context: p.Context(current: projectDirPath)));

      final projectFiles = await Directory(projectDirPath)
          .list(recursive: true)
          .where((entry) => entry is File)
          .map((file) => file.uri)
          .where((uri) =>
              !excludeGlobs.any((glob) => glob.matches(uri.toFilePath())))
          .toList();

      buildOutput.dependencies.dependencies.addAll(projectFiles);
      buildOutput.dependencies.dependencies.addAll(dartBuildFiles);
    }
  }
}

extension on OS {
  String mesonNinjaDylibFileName(String target) => switch (this) {
        // When using the Ninja backend Meson uses the the lib prefix even for
        // shared libraries on Windows.
        OS.windows => 'lib$target.dll',
        _ => dylibFileName(target),
      };
}

({String? path, String name}) _parseMesonTarget(String target) {
  final parts = target.split('/');
  if (parts.length >= 2) {
    return (
      path: parts.sublist(0, parts.length - 1).join('/'),
      name: parts.last
    );
  } else {
    return (path: null, name: target);
  }
}

extension on LinkMode {
  String get mesonTargetType => switch (this) {
        LinkMode.dynamic => 'shared_library',
        LinkMode.static => 'static_library',
        _ => throw UnimplementedError(),
      };
  String get libraryType => switch (this) {
        LinkMode.dynamic => 'shared',
        LinkMode.static => 'static',
        _ => throw UnimplementedError(),
      };
}
