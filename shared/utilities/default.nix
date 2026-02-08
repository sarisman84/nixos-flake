{
  ...
}:
{
    getDirectoryNames = directories:
        builtins.filter (name: directories.${name} == "directory") (builtins.attrNames directories);

}
