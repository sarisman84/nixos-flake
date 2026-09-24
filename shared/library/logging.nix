{lib, ...}: let
  logLevel = let
    raw = builtins.getEnv "NIXOS_LOG";
  in
    if raw == null || raw == "" || raw == "0"
    then 0
    else if raw == "2"
    then 2
    else 1;

  format = level: msg: let
    label =
      {
        "0" = "ERROR";
        "1" = "INFO";
        "2" = "DEBUG";
      }
        .${
        toString level
      }
        or "?????";
  in "[${label}] ${msg}";

  filter = entries:
    lib.filter (e: e.level <= logLevel) entries;

  toScript = entries: let
    filtered = filter entries;
  in
    if filtered == []
    then ""
    else ''
      echo "=== nixos-flake evaluation log ==="
      ${lib.concatMapStringsSep "\n" (e: "echo '${format e.level e.msg}'") filtered}
      echo "================================="
    '';

  toModule = entries: let
    script = toScript entries;
  in
    if script == ""
    then {}
    else {
      system.activationScripts.evalLog = {
        text = script;
        deps = [];
        always = true;
      };
    };
in {
  inherit format filter toScript toModule;
}
