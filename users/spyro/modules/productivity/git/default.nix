{ pkgs, ... }:
{
    home = {
        packages = with pkgs; [
            github-cli
        ];
    };

    programs.git = {
        enable = true;

        settings = {
            init.defaultBranch = "dev";
            user = {
                email = "spyridonpassas0325@gmail.com";
                name = "Spyridon Passas";
            };
        };

        signing = {
            key = "135DB2D8C73DB9CC";
            signByDefault = true;
        };

        lfs.enable = true;
    };

   services.ssh-agent = {
        enable = true;
   };

   programs.ssh = {
        matchBlocks = {
            "github.com" = {
                identityFile = "/home/spyro/.ssh/id_ed25519";
                addKeysToAgent = "yes";
            };
        };
   };

   systemd.user.sessionVariables = {
        SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/ssh-agent";
   };
}