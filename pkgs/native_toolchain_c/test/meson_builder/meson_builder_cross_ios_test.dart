// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('mac-os')
@OnPlatform({
  'mac-os': Timeout.factor(2),
})
library;

import 'dart:io';

import 'package:native_assets_cli/native_assets_cli.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
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
    Target.iOSArm64,
    Target.iOSX64,
  ];

  // Dont include 'mach-o' or 'Mach-O', different spelling is used.
  const objdumpFileFormat = {
    Target.iOSArm64: 'arm64',
    Target.iOSX64: '64-bit x86-64',
  };

  const name = 'add';

  for (final linkMode in LinkMode.values) {
    for (final targetIOSSdk in IOSSdk.values) {
      for (final target in targets) {
        if (target == Target.iOSX64 && targetIOSSdk == IOSSdk.iPhoneOs) {
          continue;
        }

        final libName = target.os.libraryFileName(name, linkMode);

        final suffix = testSuffix([linkMode, target, targetIOSSdk]);

        test('MesonBuilder library$suffix', () async {
          final tempUri = await tempDirForTest();
          final buildConfig = BuildConfig(
            outDir: tempUri,
            packageRoot: mesonAddLibProjectUri,
            targetArchitecture: target.architecture,
            targetOs: target.os,
            buildMode: BuildMode.release,
            linkModePreference: linkMode == LinkMode.dynamic
                ? LinkModePreference.dynamic
                : LinkModePreference.static,
            targetIOSSdk: targetIOSSdk,
          );
          final buildOutput = BuildOutput();

          final mesonBuilder = MesonBuilder.library(
            assetId: name,
            project: 'meson_project',
            target: name,
          );
          await mesonBuilder.run(
            buildConfig: buildConfig,
            buildOutput: buildOutput,
            logger: logger,
          );

          final libUri = tempUri.resolve(libName);
          final objdumpResult = await runProcess(
            executable: Uri.file('objdump'),
            arguments: ['-t', libUri.path],
            logger: logger,
          );
          expect(objdumpResult.exitCode, 0);
          final machine = objdumpResult.stdout
              .split('\n')
              .firstWhere((e) => e.contains('file format'));
          expect(machine, contains(objdumpFileFormat[target]));

          final otoolResult = await runProcess(
            executable: Uri.file('otool'),
            arguments: ['-l', libUri.path],
            logger: logger,
          );
          expect(otoolResult.exitCode, 0);
          if (targetIOSSdk == IOSSdk.iPhoneOs || target == Target.iOSX64) {
            // The x64 simulator behaves as device, presumably because the
            // devices are never x64.
            expect(otoolResult.stdout, contains('LC_VERSION_MIN_IPHONEOS'));
            expect(otoolResult.stdout, isNot(contains('LC_BUILD_VERSION')));
          } else {
            expect(
                otoolResult.stdout, isNot(contains('LC_VERSION_MIN_IPHONEOS')));
            expect(otoolResult.stdout, contains('LC_BUILD_VERSION'));
            final platform = otoolResult.stdout
                .split('\n')
                .firstWhere((e) => e.contains('platform'));
            const platformIosSimulator = 7;
            expect(platform, contains(platformIosSimulator.toString()));
          }

          if (linkMode == LinkMode.dynamic) {
            final libInstallName = await runOtoolInstallName(libUri, libName);
            expect(libInstallName, '@rpath/$libName');
          }
        });
      }
    }
  }
}
