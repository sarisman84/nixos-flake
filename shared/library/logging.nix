{lib, ...}: let
  # Read the NIXOS_LOG environment variable.
  # Supported values:
  #   "0" or unset  -> logging disabled (default)
  #   "1"           -> info + error
  #   "2"           -> verbose (adds debug)
  logLevel = let
    raw = builtins.getEnv "NIXOS_LOG";
  in
    if raw == null || raw == "" || raw == "0"
    then 0
    else if raw == "2"
    then 2
    else 1;

  # Format a single log line with a level prefix.
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
in {
  # info: logged when NIXOS_LOG >= 1. Returns value.
  info = msg: value:
    if logLevel >= 1
    then builtins.trace (format 1 msg) value
    else value;

  # debug: logged when NIXOS_LOG >= 2. Returns value.
  debug = msg: value:
    if logLevel >= 2
    then builtins.trace (format 2 msg) value
    else value;

  # error: always logged. Returns value.
  error = msg: value:
    builtins.trace (format 0 msg) value;

  # Exposed for callers that need the level or format.
  inherit logLevel format;
}
