{  pkgs, ... }:
{
    # GPG Setup for Git specifically
    programs.gpg = {
        enable = true;
    };

     services.gpg-agent = with pkgs; {
         enable = true;
         enableSshSupport = true;
         pinentry.package = pinentry-qt;

         defaultCacheTtl = 3600; # Default from Gemeni
         maxCacheTtl = 86400; # Default from Gemeni
     };
}