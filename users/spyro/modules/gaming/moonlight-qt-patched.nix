{ pkgs } :
with pkgs; moonlight-qt.overrideAttrs(oldAttrs: {
   nativeBuildInputs =
    (oldAttrs.nativeBuildInputs or []) ++ [ pkgs.makeWrapper ];

   postInstall = (oldAttrs.postInstall or "") + ''
      wrapProgram $out/bin/moonlight \
        --set QT_QPA_PLATFORM xcb
    '';
  }
)