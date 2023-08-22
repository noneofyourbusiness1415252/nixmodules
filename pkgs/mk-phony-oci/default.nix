{ system
, bash
, lib
, coreutils
, closureInfo
, gnutar
, gzip
, ztoc-rs
}:

{ module, moduleId }:
let
  sanitizedModuleId = builtins.replaceStrings [ ":" ] [ "_" ] moduleId;
in
derivation {
  name = "oci-image-${sanitizedModuleId}";
  builder = "${bash}/bin/bash";
  args = [ ./builder.sh ];
  inherit system;
  __structuredAttrs = true;
  unsafeDiscardReferences.out = true;
  outputs = [ "out" ];
  env = {
    MODULE_ID = moduleId;
    PATH = lib.makeBinPath [
      coreutils
      coreutils
      gnutar
      ztoc-rs
      gzip
    ];
    diskClosureInfo = closureInfo { rootPaths = [ module ]; };
  };
}
