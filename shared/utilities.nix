{
  ...
}:
{
    getDirectoryNames = directories:
        builtins.filter (name: directories.${name} == "directory") (builtins.attrNames directories);
        
    getFileNames = directories:
        builtins.filter (name: directories.${name} == "regular") (builtins.attrNames directories);
}
