{
  ...
}:
{
    getDirectoryNames = directories:
        builtins.filter (name: directories.${name} == "directory") (builtins.attrNames directories);

    getNixFileNames = directories:
        builtins.filter (name: directories.${name} == "regular" && builtins.match ".*\\.nix" name != null) (builtins.attrNames directories);
}
