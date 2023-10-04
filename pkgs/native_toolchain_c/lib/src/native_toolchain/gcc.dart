// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:native_assets_cli/native_assets_cli.dart';

import '../tool/tool.dart';
import '../tool/tool_resolver.dart';

/// The GNU Compiler Collection.
///
/// https://gcc.gnu.org/
final gcc = Tool(name: 'GCC');

/// The GNU GCC archiver.
final gnuArchiver = Tool(name: 'GNU archiver');

/// The GNU linker.
///
/// https://ftp.gnu.org/old-gnu/Manuals/ld-2.9.1/ld.html
final gnuLinker = Tool(name: 'GNU linker');

/// The GNU object stripping tool.
///
/// https://ftp.gnu.org/old-gnu/Manuals/binutils-2.12/html_node/binutils_10.html
final gnuStrip = Tool(name: 'GNU body stripping tool');

/// [gcc] with [Tool.defaultResolver] for [Architecture.ia32].
final i686LinuxGnuGcc = _gcc('i686-linux-gnu');

/// [gnuArchiver] with [Tool.defaultResolver] for [Architecture.ia32].
final i686LinuxGnuGccAr = _gnuArchiver('i686-linux-gnu');

/// [gnuLinker] with [Tool.defaultResolver] for [Architecture.ia32].
final i686LinuxGnuLd = _gnuLinker('i686-linux-gnu');

/// [gnuStrip] with [Tool.defaultResolver] for [Architecture.ia32].
final i686LinuxGnuStrip = _gnuStrip('i686-linux-gnu');

/// [gcc] with [Tool.defaultResolver] for [Architecture.arm].
final armLinuxGnueabihfGcc = _gcc('arm-linux-gnueabihf');

/// [gnuArchiver] with [Tool.defaultResolver] for [Architecture.arm].
final armLinuxGnueabihfGccAr = _gnuArchiver('arm-linux-gnueabihf');

/// [gnuLinker] with [Tool.defaultResolver] for [Architecture.arm].
final armLinuxGnueabihfLd = _gnuLinker('arm-linux-gnueabihf');

/// [gnuStrip] with [Tool.defaultResolver] for [Architecture.arm].
final armLinuxGnueabihfStrip = _gnuStrip('arm-linux-gnueabihf');

/// [gcc] with [Tool.defaultResolver] for [Architecture.arm64].
final aarch64LinuxGnuGcc = _gcc('aarch64-linux-gnu');

/// [gnuArchiver] with [Tool.defaultResolver] for [Architecture.arm64].
final aarch64LinuxGnuGccAr = _gnuArchiver('aarch64-linux-gnu');

/// [gnuLinker] with [Tool.defaultResolver] for [Architecture.arm64].
final aarch64LinuxGnuLd = _gnuLinker('aarch64-linux-gnu');

/// [gnuStrip] with [Tool.defaultResolver] for [Architecture.arm64].
final aarch64LinuxGnuStrip = _gnuStrip('aarch64-linux-gnu');

Tool _gcc(String prefix) => Tool(
      name: gcc.name,
      defaultResolver: CliVersionResolver(
        wrappedResolver: PathToolResolver(
          toolName: gcc.name,
          executableName: '$prefix-gcc',
        ),
      ),
    );

Tool _gnuArchiver(String prefix) {
  final gcc = _gcc(prefix);
  return Tool(
    name: gnuArchiver.name,
    defaultResolver: RelativeToolResolver(
      toolName: gnuArchiver.name,
      wrappedResolver: gcc.defaultResolver!,
      relativePath: Uri.file('$prefix-gcc-ar'),
    ),
  );
}

Tool _gnuLinker(String prefix) {
  final gcc = _gcc(prefix);
  return Tool(
    name: gnuLinker.name,
    defaultResolver: RelativeToolResolver(
      toolName: gnuLinker.name,
      wrappedResolver: gcc.defaultResolver!,
      relativePath: Uri.file('$prefix-ld'),
    ),
  );
}

Tool _gnuStrip(String prefix) {
  final gcc = _gcc(prefix);
  return Tool(
    name: gnuStrip.name,
    defaultResolver: RelativeToolResolver(
      toolName: gnuStrip.name,
      wrappedResolver: gcc.defaultResolver!,
      relativePath: Uri.file('$prefix-strip'),
    ),
  );
}
