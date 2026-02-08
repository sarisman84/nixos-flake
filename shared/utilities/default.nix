{
  config,
  pkgs,
  lib,
  home-manager,
  ...
}:
with lib;
{
    getDirectoryNames = directories:
        builtins.filter (name: directories.${name} == "directory") (builtins.attrNames directories);

}
