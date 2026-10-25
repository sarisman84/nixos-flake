{ lib, pkgs, config, ... }:

{
  # Time zone — UTC is typical for a headless server.
  time.timeZone = "UTC";

  # Internationalisation.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.supportedLocales = [ "en_US.UTF-8" ];
}
