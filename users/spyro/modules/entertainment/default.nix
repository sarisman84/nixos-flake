{pkgs, ...}:
{
   imports = [
     ./gaming
   ];

   home = {
    packages = with pkgs; [
       spotify
    ];
   };
}