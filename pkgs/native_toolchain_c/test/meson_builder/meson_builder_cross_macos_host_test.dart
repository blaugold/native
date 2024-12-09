// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('mac-os')
@OnPlatform({
  'mac-os': Timeout.factor(2),
})
library;

import 'dart:io';

import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:native_toolchain_c/src/cbuilder/linkmode.dart';
import 'package:native_toolchain_c/src/utils/run_process.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'helpers.dart';

void main() {
  if (!Platform.isMacOS) {
    // Avoid needing status files on Dart SDK CI.
    return;
  }

  const targets = [
    Target.macOSArm64,
    Target.macOSX64,
  ];

  // Dont include 'mach-o' or 'Mach-O', different spelling is used.
  const objdumpFileFormat = {
    Target.macOSArm64: 'arm64',
    Target.macOSX64: '64-bit x86-64',
  };

  for (final linkModePreference in LinkModePreference.values) {
    for (final target in targets) {
      final suffix = testSuffix([linkModePreference, target]);
      test('MesonBuilder library$suffix', () async {
        final tempUri = await tempDirForTest();
        final tempUri2 = await tempDirForTest();

        const name = 'add';

        final buildConfigBuilder = BuildConfigBuilder()
          ..setupHookConfig(
            buildAssetTypes: [CodeAsset.type],
            packageName: 'dummy',
            packageRoot: mesonAddLibProjectUri,
            targetOS: target.os,
            buildMode: BuildMode.release,
          )
          ..setupBuildConfig(
            linkingEnabled: false,
            dryRun: false,
          )
          ..setupCodeConfig(
            targetArchitecture: target.architecture,
            linkModePreference: linkModePreference,
          );
        buildConfigBuilder.setupBuildRunConfig(
          outputDirectory: tempUri,
          outputDirectoryShared: tempUri2,
        );
        final buildConfig = BuildConfig(buildConfigBuilder.json);
        final buildOutput = BuildOutputBuilder();

        final mesonBuilder = MesonBuilder.library(
          assetName: name,
          project: 'meson_project',
          target: name,
        );
        await mesonBuilder.run(
          config: buildConfig,
          output: buildOutput,
          logger: logger,
        );

        final libUri = tempUri.resolve(target.os.libraryFileName(
          name,
          getLinkMode(linkModePreference),
        ));
        final result = await runProcess(
          executable: Uri.file('objdump'),
          arguments: ['-t', libUri.path],
          logger: logger,
        );
        expect(result.exitCode, 0);
        final machine = result.stdout
            .split('\n')
            .firstWhere((e) => e.contains('file format'));
        expect(machine, contains(objdumpFileFormat[target]));
      });
    }
  }
}
