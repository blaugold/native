// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:ffi';
import 'dart:io';

import 'package:native_assets_cli/native_assets_cli.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:native_toolchain_c/src/utils/run_process.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'helpers.dart';

void main() {
  for (final buildMode in BuildMode.values) {
    final suffix = testSuffix([buildMode]);

    test('CBuilder executable$suffix', () async {
      final tempUri = await tempDirForTest();
      const name = 'hello_world';

      final buildConfig = BuildConfig(
        outDir: tempUri,
        packageName: name,
        packageRoot: mesonHelloWorldProjectUri,
        targetArchitecture: Architecture.current,
        targetOs: OS.current,
        buildMode: buildMode,
        // Ignored by executables.
        linkModePreference: LinkModePreference.dynamic,
        cCompiler: CCompilerConfig(
          cc: cc,
          envScript: envScript,
          envScriptArgs: envScriptArgs,
        ),
      );
      final buildOutput = BuildOutput();
      final mesonBuilder = MesonBuilder.executable(
        project: 'meson_project',
        target: name,
      );
      await mesonBuilder.run(
        buildConfig: buildConfig,
        buildOutput: buildOutput,
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
        final tempDir = await tempDirForTest();

        final buildConfig = dryRun
            ? BuildConfig.dryRun(
                outDir: tempDir,
                packageName: 'dummy',
                packageRoot: mesonAddLibProjectUri,
                targetOs: OS.current,
                linkModePreference: LinkModePreference.dynamic,
              )
            : BuildConfig(
                outDir: tempDir,
                packageName: 'dummy',
                packageRoot: mesonAddLibProjectUri,
                targetOs: OS.current,
                linkModePreference: LinkModePreference.dynamic,
                buildMode: buildMode,
                targetArchitecture: Architecture.current,
              );
        final buildOutput = BuildOutput();

        final builder = MesonBuilder.library(
          assetId: '$name.dart',
          project: 'meson_project',
          target: name,
        );
        await builder.run(
          buildConfig: buildConfig,
          buildOutput: buildOutput,
          logger: logger,
        );

        if (dryRun) {
          expect(
            buildOutput.assets.map((asset) => asset.target),
            containsAll(Target.values.where((asset) => asset.os == OS.current)),
          );
          for (final asset in buildOutput.assets) {
            expect(await asset.path.exists(), isFalse);
          }
        } else {
          final libUri =
              tempDir.resolve(buildConfig.targetOs.dylibFileName(name));
          final asset = buildOutput.assets.single;
          final assetPath = asset.path as AssetAbsolutePath;
          expect(asset.target, Target.current);
          expect(await asset.path.exists(), isTrue);
          expect(libUri, assetPath.uri);

          final library = openDynamicLibraryForTest(assetPath.uri.toFilePath());
          final add = library.lookupFunction<Int32 Function(Int32, Int32),
              int Function(int, int)>('add');
          expect(add(1, 2), 3);
        }
      });
    }
  }
}
