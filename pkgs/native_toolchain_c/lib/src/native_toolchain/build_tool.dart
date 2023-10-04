// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../tool/tool.dart';
import '../tool/tool_resolver.dart';

final Tool meson = Tool(
  name: 'Meson',
  defaultResolver: CliVersionResolver(
    wrappedResolver: ToolResolvers([
      PathToolResolver(toolName: 'Meson', executableName: 'meson'),
      HomebrewExecutableResolver(toolName: 'Meson', executableName: 'meson'),
      PythonExecutableResolver(toolName: 'Meson', executableName: 'meson'),
    ]),
  ),
);

final Tool ninja = Tool(
  name: 'Ninja',
  defaultResolver: CliVersionResolver(
    wrappedResolver: ToolResolvers([
      PathToolResolver(toolName: 'Ninja', executableName: 'ninja'),
      HomebrewExecutableResolver(toolName: 'Ninja', executableName: 'ninja'),
      PythonExecutableResolver(toolName: 'Meson', executableName: 'meson'),
    ]),
  ),
);
