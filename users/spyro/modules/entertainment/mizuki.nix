{
  pkgs,
  lib,
  ...
}:

let
  version = "0.50.1";

  src = pkgs.fetchurl {
    url = "https://github.com/Anisurge/App/releases/download/v${version}/Mizuki-linux-amd64-portable.zip";
    sha256 = "540c81173d37c53204437f71ddb30e2f6abfca2684d68d3b7261fa91ecb2be09";
  };

  # System libraries the bundled mpv and JBR resolve at runtime
  # (ldd over the portable zip's lib/mpv/*.so and lib/runtime/lib/*.so).
  runtimeDeps = [
    pkgs.alsa-lib
    pkgs.dbus
    # The bundled mpv links flite's voice libraries (libflite_cmu_us_*.so.1),
    # which live in the lib output, not the default bin output.
    pkgs.flite.lib
    # The bundled mpv also links the GCC OpenMP runtime (libgomp.so.1),
    # which lives in the lib output of the default compiler.
    pkgs.gcc.cc.lib
    pkgs.gccNGPackages_15.libstdcxx
    pkgs.libdrm
    pkgs.libxcb
    pkgs.libxkbcommon
    pkgs.libglvnd
    pkgs.libgbm
    pkgs.mesa
    # libselinux.so.1 lives in the out output, not the default bin output.
    pkgs.selinuxPackages.libselinux.out
    pkgs.systemdLibs
    # The bundled mpv links libmount.so.1, which lives in the lib output.
    pkgs.util-linux.lib
    pkgs.vulkan-loader
    pkgs.wayland
    pkgs.libx11
    pkgs.libxcursor
    pkgs.libxext
    pkgs.libxfixes
    pkgs.libxi
    # The extracted JNativeHook global-keyboard library links libXinerama.so.1.
    pkgs.libxinerama
    pkgs.libxrandr
    pkgs.libxrender
    pkgs.libxscrnsaver
    # The extracted JNativeHook global-keyboard library links libXt.so.6.
    pkgs.libxt
    pkgs.libxtst
    pkgs.libxv
  ];

  mizuki = pkgs.stdenv.mkDerivation {
    pname = "mizuki";
    inherit version src;

    nativeBuildInputs = [
      pkgs.libgcc
      pkgs.makeWrapper
      pkgs.patchelf
      pkgs.unzip
    ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p $out
      cp -a . $out
      chmod +x $out/bin/Mizuki

      # The prebuilt binaries keep the stock /lib64 interpreter, which is a
      # stub on NixOS; repoint them at the store's dynamic linker.
      patchelf --set-interpreter $(cat $NIX_CC/nix-support/dynamic-linker) \
        $out/bin/Mizuki \
        $out/lib/runtime/lib/jexec \
        $out/lib/runtime/lib/jspawnhelper

      # The NG libgcc builds (libstdc++'s RUNPATH target) carry an
      # executable-stack GNU_STACK flag that the kernel refuses to load for
      # shared objects. Ship a clean copy in $out/lib; LD_LIBRARY_PATH is
      # searched before libstdc++'s RUNPATH.
      install -Dm644 ${pkgs.libgcc}/lib/libgcc_s.so.1 $out/lib/libgcc_s.so.1

      # The bundled AppRun looks for a binary named AniSurgeX, but this
      # release ships bin/Mizuki, so wrap it directly.
      makeWrapper $out/bin/Mizuki $out/bin/mizuki \
        ${lib.concatMapStringsSep " " (p: "--prefix LD_LIBRARY_PATH : ${p}/lib") runtimeDeps} \
        --prefix LD_LIBRARY_PATH : "$out/lib/mpv" \
        --prefix LD_LIBRARY_PATH : "$out/lib"

      rm -f $out/Anisurge.desktop
      mkdir -p $out/share/applications
      cat > $out/share/applications/mizuki.desktop <<'EOF'
[Desktop Entry]
Name=Mizuki
Comment=Free and open source anime streaming app
Exec=mizuki
Icon=mizuki
Type=Application
Categories=AudioVideo;Video;
EOF

      mkdir -p $out/share/icons/hicolor/1024x1024/apps
      cp $out/Mizuki.png $out/share/icons/hicolor/1024x1024/apps/mizuki.png
    '';

    meta = with lib; {
      description = "Free and open source anime streaming app (formerly AniSurge)";
      homepage = "https://anisurge.lol/";
      license = licenses.unfree;
      platforms = platforms.linux;
      mainProgram = "mizuki";
    };
  };
in
{
  home.packages = [ mizuki ];
}
