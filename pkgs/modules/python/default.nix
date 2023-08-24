{ python, pypkgs }:
{ pkgs, lib, ... }:
let
  community-version = lib.versions.majorMinor python.version;

  pylibs-dir = ".pythonlibs";

  pip = pkgs.callPackage ../../pip {
    inherit pypkgs;
  };

  pip-config = pkgs.writeTextFile {
    name = "pip.conf";
    text = ''
      [global]
      user = yes
      disable-pip-version-check = yes
      index-url = https://package-proxy.replit.com/pypi/simple/

      [install]
      use-feature = content-addressable-pool
      content-addressable-pool-symlink = yes
    '';
  };

  pythonWrapper = { bin, name, aliases ? [ ] }:
    let
      ldLibraryPathConvertWrapper = pkgs.writeShellScriptBin name ''
        export LD_LIBRARY_PATH=''${PYTHON_LD_LIBRARY_PATH}
        exec "${bin}" "$@"
      '';
    in
    pkgs.stdenvNoCC.mkDerivation {
      name = "${name}-wrapper";
      buildInputs = [ pkgs.makeWrapper ];

      buildCommand = ''
        mkdir -p $out/bin
        makeWrapper ${ldLibraryPathConvertWrapper}/bin/${name} $out/bin/${name} \
          --set-default PYTHON_LD_LIBRARY_PATH "${python-ld-library-path}" \
          --prefix PYTHONPATH : "${pypkgs.setuptools}/${python.sitePackages}"
      '' + lib.concatMapStringsSep "\n" (s: "ln -s $out/bin/${name} $out/bin/${s}") aliases;

    };

  pip-wrapper = pythonWrapper { bin = "${pip}/bin/pip"; name = "pip"; };

  poetry = pkgs.callPackage ../../poetry {
    inherit python;
    inherit pypkgs;
  };

  poetry-config = pkgs.writeTextFile {
    name = "poetry-config";
    text = ''
      [[tool.poetry.source]]
      name = "replit"
      url = "https://package-proxy.replit.com/pypi/simple/"
      default = true
    '';
    destination = "/conf.toml";
  };

  cppLibs = pkgs.stdenvNoCC.mkDerivation {
    name = "cpplibs";
    dontUnpack = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib
      cp ${pkgs.stdenv.cc.cc.lib}/lib/libstdc++* $out/lib

      runHook postInstall
    '';
  };

  prybar-python = pkgs.prybar.prybar-python310;

  stderred = pkgs.callPackage ../../stderred { };

  debugpy = pypkgs.debugpy;

  dapPython = pkgs.callPackage ../../dapPython {
    inherit pkgs python pypkgs;
  };

  python-ld-library-path = pkgs.lib.makeLibraryPath ([
    # Needed for pandas / numpy
    cppLibs
    pkgs.zlib
    pkgs.glib
    # Needed for matplotlib
    pkgs.xorg.libX11
    # Needed for pygame
  ] ++ (with pkgs.xorg; [ libXext libXinerama libXcursor libXrandr libXi libXxf86vm ]));

  python3-wrapper = pythonWrapper { bin = "${python}/bin/python3"; name = "python3"; aliases = [ "python" "python${community-version}" ]; };

  run-prybar-bin = pkgs.writeShellScriptBin "run-prybar" ''
    ${stderred}/bin/stderred -- ${prybar-python}/bin/prybar-python310 -q --ps1 "''$(printf '\u0001\u001b[33m\u0002\u0001\u001b[00m\u0002 ')" -i ''$1
  '';

  run-prybar = pythonWrapper { bin = "${run-prybar-bin}/bin/run-prybar"; name = "run-prybar"; };

  poetry-wrapper = pythonWrapper { bin = "${poetry}/bin/poetry"; name = "poetry"; };

  pyright-extended = pkgs.callPackage ../../pyright-extended { };

in
{
  id = "python-${community-version}";
  name = "Python ${community-version} Tools";

  packages = [
    python3-wrapper
    pip-wrapper
    poetry-wrapper
    run-prybar
  ];

  replit.runners.python = {
    name = "Python ${community-version}";
    fileParam = true;
    language = "python3";
    start = "${python3-wrapper}/bin/python3 $file";
  };

  replit.runners.python-prybar = {
    name = "Prybar for Python ${community-version}";
    optionalFileParam = true;
    language = "python3";
    start = "${run-prybar}/bin/run-prybar $file";
    interpreter = true;
  };

  replit.debuggers.dapPython = {
    name = "DAP Python";
    language = "python3";
    start = {
      args = [ "${dapPython}/bin/dap-python" "$file" ];
    };
    fileParam = true;
    transport = "localhost:0";
    integratedAdapter = {
      dapTcpAddress = "localhost:0";
    };
    initializeMessage = {
      command = "initialize";
      type = "request";
      arguments = {
        adapterID = "debugpy";
        clientID = "replit";
        clientName = "replit.com";
        columnsStartAt1 = true;
        linesStartAt1 = true;
        locale = "en-us";
        pathFormat = "path";
        supportsInvalidatedEvent = true;
        supportsProgressReporting = true;
        supportsRunInTerminalRequest = true;
        supportsVariablePaging = true;
        supportsVariableType = true;
      };
    };
    launchMessage = {
      command = "attach";
      type = "request";
      arguments = {
        logging = { };
      };
    };
  };

  replit.languageServers.pyright-extended = {
    name = "pyright-extended";
    language = "python3";
    start = "${pyright-extended}/bin/langserver.index.js --stdio";
  };

  replit.packagers.upmPython = {
    name = "Python";
    language = "python3";
    ignoredPackages = [ "unit_tests" ];
    ignoredPaths = [ pylibs-dir ];
    features = {
      packageSearch = true;
      guessImports = true;
      enabledForHosting = false;
    };
  };

  replit.env =
    let userbase = "$REPL_HOME/${pylibs-dir}";
    in {
      PYTHONPATH = "${python}/lib/python${community-version}:${userbase}/${python.sitePackages}";
      PIP_CONFIG_FILE = pip-config.outPath;
      POETRY_CONFIG_DIR = poetry-config.outPath;
      POETRY_CACHE_DIR = "$REPL_HOME/.cache/pypoetry";
      POETRY_VIRTUALENVS_CREATE = "0";
      POETRY_INSTALLER_MODERN_INSTALLATION = "0";
      POETRY_PIP_USE_PIP_CACHE = "1";
      POETRY_PIP_NO_ISOLATE = "1";
      POETRY_PIP_NO_PREFIX = "1";
      POETRY_PIP_FROM_PATH = "1";
      POETRY_USE_USER_SITE = "1";
      PYTHONUSERBASE = userbase;
      # Even though it is set-default in the wrapper, add it to the
      # environment too, so that when someone wants to override it,
      # they can keep the defaults if they want to.
      PYTHON_LD_LIBRARY_PATH = python-ld-library-path;
      PATH = "${userbase}/bin";
    };
}
