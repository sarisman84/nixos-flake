{ pkgs }: with pkgs; modrinth-app.overrideAttrs (oldAttrs: {
  nativeBuildInputs =
    (oldAttrs.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];

  buildCommand =
    ''
      					gappsWrapperArgs+=(
      						--set GDK_BACKEND x11
      						--set WEBKIT_DISABLE_DMABUF_RENDERER 1
      					)
      				''
    + oldAttrs.buildCommand;
})
