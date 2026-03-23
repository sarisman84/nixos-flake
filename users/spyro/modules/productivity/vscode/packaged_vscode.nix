{pkgs, ...}:
let
  dotnet = with pkgs.dotnetCorePackages;
    combinePackages [
      aspnetcore_10_0
      runtime_10_0
      sdk_10_0
    ];
  deps = (
    ps:
      [ dotnet ]
  );
in
{
  vscode = (pkgs.vscode.overrideAttrs (prevAttrs: {
          nativeBuildInputs = prevAttrs.nativeBuildInputs ++ [ pkgs.makeWrapper ];
          postFixup =
            prevAttrs.postFixup
            + ''
              wrapProgram $out/bin/code \
                --set DOTNET_ROOT "${dotnet}" \
                --prefix PATH : "~/.dotnet/tools"
            '';
        })).fhsWithPackages (ps: deps ps);
}