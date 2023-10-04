import 'dart:io';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:native_assets_cli/native_assets_cli.dart';
import 'package:pub_semver/pub_semver.dart';

import '../cbuilder/compiler_resolver.dart';
import '../native_toolchain/build_tool.dart';
import '../native_toolchain/xcode.dart';
import '../tool/tool.dart';
import '../tool/tool_error.dart';
import '../tool/tool_instance.dart';
import '../utils/env_from_bat.dart';
import '../utils/run_process.dart';

// TODO: Support static libraries
// TODO: Support shared libraries
// TODO: Support executables
// TODO: Support for cpp
// TODO: Support for objc & objcpp
// TODO: Strip binaries when launcher provides tools
// TODO: Figure out how to resolve the precise CPU name.
// TODO: Figure out if there are any big endian targets.
// TODO: Support pkg-config (binaries, sys_root, pkg_config_libdir)
// TODO: Support cmake
// TODO: Deployment targets
//         - ios-version-min
//         - ios-simulator-version-min
//         - macos-version-min
//         - minSdkTarget
//         - Research Windows
//         - Research Linux
// TODO: Expand support for can_run_host_binaries (provide exe_wrapper binaries)
// TODO: Find ccache and wrap compilers with it

class RunMesonBuilder {
  static final supportedMesonVersionRange = VersionConstraint.parse('^1.0.0');

  final BuildConfig buildConfig;
  final Logger? logger;
  final Uri outDir;
  final Target target;
  final Uri projectDir;
  final String mesonTarget;
  final Map<String, String> options;
  final ToolInstance? mesonInstance;

  late final _resolver =
      CompilerResolver(buildConfig: buildConfig, logger: logger);

  RunMesonBuilder({
    required this.buildConfig,
    required this.logger,
    required this.projectDir,
    required this.mesonTarget,
    required this.options,
    @visibleForTesting this.mesonInstance,
  })  : outDir = buildConfig.outDir,
        target = buildConfig.target;

  Future<void> run() async {
    await _cleanOutDir();

    final (
      _,
      mesonInstance,
      ninjaInstance,
      compiler,
      linker,
      archiver,
      strip,
    ) = await (
      _cleanOutDir(),
      this.mesonInstance != null
          ? Future.value(this.mesonInstance)
          : _loadToolFromNativeToolchain(meson),
      _loadToolFromNativeToolchain(ninja),
      _resolver.resolveCompiler(),
      _resolver.resolveLinker(),
      _resolver.resolveArchiver(),
      _resolver.resolveStrip(),
    ).wait;

    // TODO: Remove ignore once bug in Dart is fixed.
    // ignore: unnecessary_non_null_assertion
    if (!supportedMesonVersionRange.allows(mesonInstance!.version!)) {
      final errorMessage =
          'Meson version ${mesonInstance.version} is in the range of supported '
          'versions ($supportedMesonVersionRange).';
      logger?.severe(errorMessage);
      throw ToolError(errorMessage);
    }

    final compilerEnvironment = await _compilerEnvironment(compiler);
    final crossFile = await _generateCrossFile(
      compiler: compiler,
      linker: linker,
      archiver: archiver,
      strip: strip,
    );

    // Configure the build.
    await runProcess(
      executable: mesonInstance.uri,
      arguments: [
        'setup',
        '--backend',
        'ninja',
        '--cross',
        crossFile.toFilePath(),
        for (final MapEntry(key: name, :value) in options.entries)
          '-D$name=$value',
        outDir.toFilePath(),
      ],
      environment: compilerEnvironment,
      throwOnUnexpectedExitCode: true,
      workingDirectory: projectDir,
      logger: logger,
    );

    // Run the build.
    await runProcess(
      executable: mesonInstance.uri,
      arguments: [
        'compile',
        '-C',
        outDir.toFilePath(),
        mesonTarget,
      ],
      environment: {
        'PATH': '${ninjaInstance.uri.toFilePath()}:'
            '${Platform.environment['PATH']!}',
      },
      throwOnUnexpectedExitCode: true,
      workingDirectory: projectDir,
      logger: logger,
    );
  }

  Future<Uri> _generateCrossFile({
    required ToolInstance compiler,
    required ToolInstance linker,
    required ToolInstance archiver,
    required ToolInstance? strip,
  }) async {
    final crossSpec = _CrossSpec()
      ..binaries.ar = archiver.uri
      ..binaries.strip = strip?.uri
      ..properties.needsExeWrapper = target != Target.current;
    _hostMachineSpec(crossSpec);
    await _cSupport(crossSpec, compiler, linker);

    final crossFileUri = outDir.resolve('cross.ini');
    await File.fromUri(crossFileUri).writeAsString(crossSpec.toIni());
    return crossFileUri;
  }

  Future<void> _cSupport(
    _CrossSpec crossSpec,
    ToolInstance compiler,
    ToolInstance linker,
  ) async {
    crossSpec.binaries
      ..c = compiler.uri
      ..cLd = linker.uri;

    final clangTarget = switch (buildConfig.targetOs) {
      OS.macOS => _appleClangMacosTargets[target],
      OS.iOS => _appleClangIosTargets[target]![buildConfig.targetIOSSdk!]!,
      OS.android => '${_androidNdkClangTargets[target]!}'
          '${buildConfig.targetAndroidNdkApi!}',
      _ => null,
    };

    final sysRoot = switch (target.os) {
      OS.macOS => await _macosSdk(logger: logger),
      OS.iOS => await _iosSdk(buildConfig.targetIOSSdk!, logger: logger),
      _ => null,
    };

    final commonArgs = [
      if (clangTarget != null) '--target=$clangTarget',
      if (sysRoot != null) ...['-isysroot', sysRoot.toFilePath()],
    ];

    crossSpec.builtInOptions.cArgs = [
      ...commonArgs,
    ];

    crossSpec.builtInOptions.cLinkArgs = [
      ...commonArgs,
      if (target.os == OS.android)
        // See the comment in RunCBuilder why this flag is being passed.
        // if (dynamicLibrary != null)
        '-nostartfiles',
    ];
  }

  void _hostMachineSpec(_CrossSpec crossSpec) {
    final hostMachine = crossSpec.hostMachine;

    hostMachine.system = switch (target.os) {
      OS.android => 'android',
      OS.iOS || OS.macOS => 'darwin',
      OS.linux => 'linux',
      OS.windows => 'windows',
      _ => throw UnimplementedError(),
    };
    hostMachine.subsystem = switch (target.os) {
      OS.iOS => switch (buildConfig.targetIOSSdk) {
          IOSSdk.iPhoneOs => 'ios',
          IOSSdk.iPhoneSimulator => 'ios-simulator',
          _ => throw UnimplementedError(),
        },
      OS.macOS => 'macos',
      _ => hostMachine.system,
    };
    hostMachine.kernel = switch (target.os) {
      OS.android || OS.linux => 'linux',
      OS.iOS || OS.macOS => 'xnu',
      OS.windows => 'nt',
      _ => throw UnimplementedError(),
    };
    hostMachine.cpuFamily = switch (target.architecture) {
      Architecture.arm => 'arm',
      Architecture.arm64 => 'aarch64',
      Architecture.ia32 => 'x86',
      Architecture.x64 => 'x86_64',
      Architecture.riscv32 => 'riscv32',
      Architecture.riscv64 => 'riscv64',
      _ => throw UnimplementedError(),
    };
    // TODO: Figure out how to resolve a more precise CPU name.
    hostMachine.cpu = hostMachine.cpuFamily;
    // TODO: Figure out if there are any big endian targets.
    hostMachine.endian = 'little';
  }

  Future<ToolInstance> _loadToolFromNativeToolchain(Tool tool) async {
    final instance = await _tryLoadToolFromNativeToolchain(tool);
    if (instance == null) {
      final errorMessage = 'Tool ${tool.name} not found.';
      logger?.severe(errorMessage);
      throw ToolError(errorMessage);
    }
    return instance;
  }

  Future<ToolInstance?> _tryLoadToolFromNativeToolchain(Tool tool) async {
    final resolved = (await tool.defaultResolver!.resolve(logger: logger))
        .where((i) => i.tool == tool)
        .toList()
      ..sort();
    return resolved.isEmpty ? null : resolved.first;
  }

  Future<Map<String, String>?> _compilerEnvironment(
    ToolInstance compiler,
  ) async {
    if (target.os == OS.windows) {
      final vcvars = (await _resolver.toolchainEnvironmentScript(compiler))!;
      final vcvarsArgs = _resolver.toolchainEnvironmentScriptArguments();
      return await envFromBat(vcvars, arguments: vcvarsArgs ?? []);
    }
    return null;
  }

  Future<Uri> _iosSdk(IOSSdk iosSdk, {required Logger? logger}) async {
    if (iosSdk == IOSSdk.iPhoneOs) {
      return (await iPhoneOSSdk.defaultResolver!.resolve(logger: logger))
          .where((i) => i.tool == iPhoneOSSdk)
          .first
          .uri;
    }
    assert(iosSdk == IOSSdk.iPhoneSimulator);
    return (await iPhoneSimulatorSdk.defaultResolver!.resolve(logger: logger))
        .where((i) => i.tool == iPhoneSimulatorSdk)
        .first
        .uri;
  }

  Future<Uri> _macosSdk({required Logger? logger}) async =>
      (await macosxSdk.defaultResolver!.resolve(logger: logger))
          .where((i) => i.tool == macosxSdk)
          .first
          .uri;

  Future<void> _cleanOutDir() async {
    final outDirectory = Directory.fromUri(outDir);
    if (outDirectory.existsSync()) {
      await outDirectory.delete(recursive: true);
    }
    await outDirectory.create(recursive: true);
  }

  static const _androidNdkClangTargets = {
    Target.androidArm: 'armv7a-linux-androideabi',
    Target.androidArm64: 'aarch64-linux-android',
    Target.androidIA32: 'i686-linux-android',
    Target.androidX64: 'x86_64-linux-android',
  };

  static const _appleClangMacosTargets = {
    Target.macOSArm64: 'arm64-apple-darwin',
    Target.macOSX64: 'x86_64-apple-darwin',
  };

  static const _appleClangIosTargets = {
    Target.iOSArm64: {
      IOSSdk.iPhoneOs: 'arm64-apple-ios',
      IOSSdk.iPhoneSimulator: 'arm64-apple-ios-simulator',
    },
    Target.iOSX64: {
      IOSSdk.iPhoneSimulator: 'x86_64-apple-ios-simulator',
    },
  };
}

class _CrossSpec {
  final hostMachine = _MachineSpec();
  final binaries = _BinariesSpec();
  final builtInOptions = _BuiltInOptionsSpec();
  final properties = _PropertiesSpec();

  String toIni() => _renderIni({
        'host_machine': hostMachine.toProperties(),
        'binaries': binaries.toProperties(),
        'built-in options': builtInOptions.toProperties(),
        'properties': properties.toProperties(),
      });
}

class _MachineSpec {
  String? system;
  String? subsystem;
  String? kernel;
  String? cpuFamily;
  String? cpu;
  String? endian;

  _IniProperties toProperties() => {
        'system': system,
        'subsystem': subsystem,
        'kernel': kernel,
        'cpu_family': cpuFamily,
        'cpu': cpu,
        'endian': endian,
      };
}

class _BuiltInOptionsSpec {
  List<String>? cArgs;
  List<String>? cLinkArgs;

  _IniProperties toProperties() => {
        'c_args': cArgs,
        'c_link_args': cLinkArgs,
      };
}

class _PropertiesSpec {
  bool? needsExeWrapper;

  _IniProperties toProperties() => {
        'needs_exe_wrapper': needsExeWrapper,
      };
}

class _BinariesSpec {
  Uri? c;
  Uri? cLd;
  Uri? ar;
  Uri? strip;

  _IniProperties toProperties() => {
        'c': c?.toFilePath(),
        'c_ld': cLd?.toFilePath(),
        'ar': ar?.toFilePath(),
        'strip': strip?.toFilePath(),
      };
}

typedef _IniProperties = Map<String, Object?>;

String _renderIni(Map<String, _IniProperties> sections) {
  String renderValue(Object value) => switch (value) {
        String() => "'$value'",
        bool() || num() => value.toString(),
        List<Object>() => '[${value.map(renderValue).join(', ')}]',
        _ => throw UnimplementedError(),
      };

  String renderSection(MapEntry<String, _IniProperties> section) {
    final MapEntry(key: name, value: properties) = section;
    return [
      '[$name]',
      for (final MapEntry(key: name, :value) in properties.entries)
        if (value != null) '$name = ${renderValue(value)}',
    ].join('\n');
  }

  return sections.entries
      .where((section) => section.value.isNotEmpty)
      .map(renderSection)
      .join('\n\n');
}
