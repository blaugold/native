// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:ffi';
import 'dart:io';

import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:native_toolchain_c/src/utils/run_process.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'helpers.dart';

void main() {
  for (final buildMode in BuildMode.values) {
    final suffix = testSuffix([buildMode]);

    test('MesonBuilder executable$suffix', () async {
      final tempUri = await tempDirForTest();
      final tempUri2 = await tempDirForTest();
      const name = 'hello_world';

      final buildConfigBuilder = BuildConfigBuilder()
        ..setupHookConfig(
          buildAssetTypes: [CodeAsset.type],
          packageName: 'dummy',
          packageRoot: mesonHelloWorldProjectUri,
          targetOS: OS.current,
          buildMode: buildMode,
        )
        ..setupBuildConfig(
          linkingEnabled: false,
          dryRun: false,
        )
        ..setupCodeConfig(
          targetArchitecture: Architecture.current,
          // Ignored by executables.
          linkModePreference: LinkModePreference.dynamic,
          cCompilerConfig: cCompiler,
        );
      buildConfigBuilder.setupBuildRunConfig(
        outputDirectory: tempUri,
        outputDirectoryShared: tempUri2,
      );
      final buildConfig = BuildConfig(buildConfigBuilder.json);
      final buildOutput = BuildOutputBuilder();

      final mesonBuilder = MesonBuilder.executable(
        project: 'meson_project',
        target: name,
      );
      await mesonBuilder.run(
        config: buildConfig,
        output: buildOutput,
        logger: logger,
      );

      final executableUri =
          tempUri.resolve(Target.current.os.executableFileName(name));
      expect(await File.fromUri(executableUri).exists(), true);
      final result = await runProcess(
        executable: executableUri,
        logger: logger,
      );
      expect(result.exitCode, 0);
      if (buildMode == BuildMode.debug) {
        expect(result.stdout.trim(), startsWith('Running in debug mode.'));
      }
      expect(result.stdout.trim(), endsWith('Hello world.'));
    });
  }

  for (final dryRun in [true, false]) {
    for (final buildMode in BuildMode.values) {
      final suffix = testSuffix([
        if (dryRun) 'dry_run',
        buildMode,
      ]);

      test('MesonBuilder library$suffix', () async {
        const name = 'add';
        final tempUri = await tempDirForTest();
        final tempUri2 = await tempDirForTest();

        final buildConfigBuilder = BuildConfigBuilder()
          ..setupHookConfig(
            buildAssetTypes: [CodeAsset.type],
            packageName: 'dummy',
            packageRoot: mesonHelloWorldProjectUri,
            targetOS: OS.current,
            buildMode: buildMode,
          )
          ..setupBuildConfig(
            linkingEnabled: false,
            dryRun: dryRun,
          )
          ..setupCodeConfig(
            targetArchitecture: Architecture.current,
            // Ignored by executables.
            linkModePreference: LinkModePreference.dynamic,
            cCompilerConfig: dryRun ? null : cCompiler,
          );
        buildConfigBuilder.setupBuildRunConfig(
          outputDirectory: tempUri,
          outputDirectoryShared: tempUri2,
        );
        final buildConfig = BuildConfig(buildConfigBuilder.json);
        final buildOutput = BuildOutputBuilder();

        final builder = MesonBuilder.library(
          assetName: '$name.dart',
          project: 'meson_project',
          target: name,
        );
        await builder.run(
          config: buildConfig,
          output: buildOutput,
          logger: logger,
        );

        final output = BuildOutput(buildOutput.json);
        final codeAssets =
            output.encodedAssets.map(CodeAsset.fromEncoded).toList();

        if (dryRun) {
          expect(
            codeAssets.map((asset) =>
                Target.fromArchitectureAndOS(asset.architecture!, asset.os)),
            containsAll(Target.values.where((asset) => asset.os == OS.current)),
          );
          for (final asset in codeAssets) {
            expect(await File.fromUri(asset.file!).exists(), isFalse);
          }
        } else {
          final libUri =
              tempUri.resolve(buildConfig.targetOS.dylibFileName(name));
          final asset = codeAssets.single;
          final assetFile = asset.file!;
          expect(asset.os, OS.current);
          expect(asset.architecture, Architecture.current);
          expect(await File.fromUri(assetFile).exists(), isTrue);
          expect(libUri, assetFile);

          final library = openDynamicLibraryForTest(assetFile.toFilePath());
          final add = library.lookupFunction<Int32 Function(Int32, Int32),
              int Function(int, int)>('add');
          expect(add(1, 2), 3);
        }
      });
    }
  }
}
