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
  final _MesonBuilderType _type;
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
  }) : _type = _MesonBuilderType.library;

  MesonBuilder.executable({
    required this.project,
    required this.target,
    this.options = const {},
    this.excludeFromDependencies = const [],
    this.dartBuildFiles = const ['build.dart'],
  })  : _type = _MesonBuilderType.executable,
        assetId = null,
        linkMode = null;

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

    final targetOutDir =
        outDir.resolve(targetPath == null ? './' : '$targetPath/');
    late final libraryUri =
        targetOutDir.resolve(buildConfig.targetOs.dylibFileName(targetName));
    late final executableUri = targetOutDir
        .resolve(buildConfig.targetOs.executableFileName(targetName));

    final dartBuildFiles = [
      for (final source in this.dartBuildFiles) packageRoot.resolve(source),
    ];

    final linkModePreference = buildConfig.linkModePreference;
    final resolvedLinkMode = linkMode ?? linkModePreference.preferredLinkMode;
    final targetWithType = '$target:${_type.mesonTargetType(resolvedLinkMode)}';

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
          if (_type == _MesonBuilderType.library)
            'default_library': resolvedLinkMode.libraryType,
        },
      );
      await task.run();
    }

    if (assetId != null) {
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
          path: AssetAbsolutePath(switch (_type) {
            _MesonBuilderType.library => libraryUri,
            _MesonBuilderType.executable => executableUri,
          }),
        ));
      }
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

enum _MesonBuilderType {
  executable,
  library,
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

extension on _MesonBuilderType {
  String mesonTargetType(LinkMode linkMode) => switch (this) {
        _MesonBuilderType.library => linkMode.mesonTargetType,
        _MesonBuilderType.executable => 'executable',
      };
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
