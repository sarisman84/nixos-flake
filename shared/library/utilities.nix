{
  lib,
  ...
}:
{
  getDirectoryNames =
    dir:
    let
      entries = builtins.readDir dir;
    in
    lib.attrNames (lib.filterAttrs (_: type: type == "directory") entries);

  getNixFileNames =
    dir:
    let
      entries =  builtins.trace ("Path: ${toString(lib.mapAttrsToList (name: value: name) (builtins.readDir dir))}") (builtins.readDir dir);
    in
    lib.attrNames (
      lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) entries
    );
}
