{pkgs, ...}: let
  listen = "127.0.0.1:8080";
  configFile = "%E/llama-swap/config.yaml";
  emptyConfig = pkgs.writeText "llama-swap-empty.yaml" "models: {}\n";
in {
  home.packages = with pkgs; [opencode opencode-desktop llama-swap llama-cpp];
  home.file.".config/opencode/AGENTS.md".source = ./AGENTS.md;

  systemd.user.services.llama-swap = {
    Unit.Description = "llama-swap local model server";
    Service = {
      ConfigurationDirectory = "llama-swap";
      # Upstream needs a config even with zero models. Seed a writable file
      # only on first start; subsequent starts preserve the user's settings.
      ExecStartPre = "${pkgs.coreutils}/bin/cp --no-preserve=mode --update=none ${emptyConfig} ${configFile}";
      ExecStart = "${pkgs.llama-swap}/bin/llama-swap -config ${configFile} -listen ${listen}";
      Environment = "PATH=${pkgs.llama-cpp}/bin:/run/current-system/sw/bin";
      Restart = "on-failure";
    };
    Install.WantedBy = ["default.target"];
  };

  xdg.desktopEntries.llama-swap = import ./desktop-entry.nix {inherit pkgs listen;};
}
