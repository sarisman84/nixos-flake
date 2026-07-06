{ pkgs, flake-inputs, ... }:
let
  ext = import ./packaged_vscode.nix { inherit pkgs; };
in
{


  imports = [
    flake-inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];

  home = {
    packages = with pkgs; [
      nodejs
      pnpm
      nil
    ];
  };

  programs = {
    vscode = {
      enable = true;
      package = ext.vscode;

      profiles.default = {
        extensions = with pkgs.vscode-extensions;
          [
            #General
            yzhang.markdown-all-in-one
            geequlim.godot-tools
            bbenoist.nix
            ms-azuretools.vscode-docker
            esbenp.prettier-vscode
            #rvest.vs-code-prettier-eslint
            ms-vscode.cpptools
            ms-vscode.cmake-tools
            #VisualStudioToolsForUnity.vstuc
            visualstudiotoolsforunity.vstuc
            #PKief.material-icon-theme

            #Themes
            dracula-theme.theme-dracula
            pkief.material-icon-theme
            mkhl.direnv

            #React/Tailwind Stuff
            #zenclabs.previewjs
            bradlc.vscode-tailwindcss
            dbaeumer.vscode-eslint
            #austenc.tailwind-docs

            # Other
            prisma.prisma

          ];
        userSettings = builtins.fromJSON (builtins.readFile ./config.json);
      };
    };


    direnv = {
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
    };
  };
}
