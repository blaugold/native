// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:native_toolchain_c/src/cbuilder/linkmode.dart';
import 'package:native_toolchain_c/src/utils/run_process.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'helpers.dart';

void main() {
  const targets = [
    Target.androidArm,
    Target.androidArm64,
    Target.androidIA32,
    Target.androidX64,
  ];

  const readElfMachine = {
    Target.androidArm: 'ARM',
    Target.androidArm64: 'AArch64',
    Target.androidIA32: 'Intel 80386',
    Target.androidX64: 'Advanced Micro Devices X86-64',
  };

  const objdumpFileFormat = {
    Target.androidArm: 'elf32-littlearm',
    Target.androidArm64: 'elf64-littleaarch64',
    Target.androidIA32: 'elf32-i386',
    Target.androidX64: 'elf64-x86-64',
  };

  /// From https://docs.flutter.dev/reference/supported-platforms.
  const flutterAndroidNdkVersionLowestSupported = 21;

  /// From https://docs.flutter.dev/reference/supported-platforms.
  const flutterAndroidNdkVersionHighestSupported = 30;

  for (final linkModePreference in LinkModePreference.values) {
    for (final target in targets) {
      final suffix = testSuffix([linkModePreference, target]);
      test('MesonBuilder library$suffix', () async {
        final tempUri = await tempDirForTest();
        final tempUri2 = await tempDirForTest();
        final libUri = await buildLib(
          tempUri,
          tempUri2,
          target,
          flutterAndroidNdkVersionLowestSupported,
          linkModePreference,
        );
        if (Platform.isLinux) {
          final result = await runProcess(
            executable: Uri.file('readelf'),
            arguments: ['-h', libUri.path],
            logger: logger,
          );
          expect(result.exitCode, 0);
          final machine = result.stdout
              .split('\n')
              .firstWhere((e) => e.contains('Machine:'));
          expect(machine, contains(readElfMachine[target]));
        } else if (Platform.isMacOS) {
          final result = await runProcess(
            executable: Uri.file('objdump'),
            arguments: ['-T', libUri.path],
            logger: logger,
          );
          expect(result.exitCode, 0);
          final machine = result.stdout
              .split('\n')
              .firstWhere((e) => e.contains('file format'));
          expect(machine, contains(objdumpFileFormat[target]));
        }
      });
    }
  }

  test('MesonBuilder API levels binary difference', () async {
    const target = Target.androidArm64;
    const linkModePreference = LinkModePreference.dynamic;
    const apiLevel1 = flutterAndroidNdkVersionLowestSupported;
    const apiLevel2 = flutterAndroidNdkVersionHighestSupported;
    final tempUri = await tempDirForTest();
    final tempUri2 = await tempDirForTest();
    final out1Uri = tempUri.resolve('out1/');
    final out2Uri = tempUri.resolve('out2/');
    final out3Uri = tempUri.resolve('out3/');
    final out1Uri2 = tempUri2.resolve('out1/');
    final out2Uri2 = tempUri2.resolve('out2/');
    final out3Uri2 = tempUri2.resolve('out3/');
    await Directory.fromUri(out1Uri).create();
    await Directory.fromUri(out2Uri).create();
    await Directory.fromUri(out3Uri).create();
    final lib1Uri = await buildLib(
      out1Uri,
      out1Uri2,
      target,
      apiLevel1,
      linkModePreference,
    );
    final lib2Uri = await buildLib(
      out2Uri,
      out2Uri2,
      target,
      apiLevel2,
      linkModePreference,
    );
    final lib3Uri = await buildLib(
      out3Uri,
      out3Uri2,
      target,
      apiLevel2,
      linkModePreference,
    );
    final bytes1 = await File.fromUri(lib1Uri).readAsBytes();
    final bytes2 = await File.fromUri(lib2Uri).readAsBytes();
    final bytes3 = await File.fromUri(lib3Uri).readAsBytes();
    // Different API levels should lead to a different binary.
    expect(bytes1, isNot(bytes2));
    // Identical API levels should lead to an identical binary.
    expect(bytes2, bytes3);
  });
}

Future<Uri> buildLib(
  Uri tempUri,
  Uri tempUri2,
  Target target,
  int androidNdkApi,
  LinkModePreference linkModePreference,
) async {
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
      targetAndroidNdkApi: androidNdkApi,
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

  return tempUri.resolve(target.os.libraryFileName(
    name,
    getLinkMode(linkModePreference),
  ));
}
