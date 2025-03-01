{
  alsa-lib,
  autoPatchelfHook,
  buildFHSEnv,
  dbus,
  elfutils,
  expat,
  extraEnv ? { },
  fetchFromGitLab,
  fetchurl,
  glib,
  glibc,
  lib,
  libGL,
  libapparmor,
  libbsd,
  libdrm,
  libedit,
  libffi_3_3,
  libgcrypt,
  libglvnd,
  makeShellWrapper,
  sqlite,
  squashfsTools,
  stdenv,
  tcp_wrappers,
  udev,
  waylandpp,
  writeShellScript,
  xkeyboard_config,
  xorg,
  xz,
  zstd,
}:
let
  pname = "plex-desktop";
  version = "1.101.0";
  rev = "75";
  meta = {
    homepage = "https://plex.tv/";
    description = "Streaming media player for Plex";
    longDescription = ''
      Plex for Linux is your client for playback on the Linux
      desktop. It features the point and click interface you see in your browser
      but uses a more powerful playback engine as well as
      some other advance features.
    '';
    maintainers = with lib.maintainers; [ detroyejr ];
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "plex-desktop";
  };

  # The latest unstable version isn't compatible with libraries that ship in the snap.
  libglvnd-1_4_0 = libglvnd.overrideAttrs {
    src = fetchFromGitLab {
      domain = "gitlab.freedesktop.org";
      owner = "glvnd";
      repo = "libglvnd";
      rev = "v1.4.0";
      sha256 = "sha256-Y6JHRygXcZtnrdnqi1Lzyvh/635gwZWnMeW9aRCpxxs";
    };
  };
  plex-desktop = stdenv.mkDerivation {
    inherit pname version meta;

    src = fetchurl {
      url = "https://api.snapcraft.io/api/v1/snaps/download/qc6MFRM433ZhI1XjVzErdHivhSOhlpf0_${rev}.snap";
      hash = "sha512-3ofO4a8HDWeUfjsv+4A5bC0jlQwxIew1CnL39Oa0bjnqShwRQjMW1vSHOjsJ1AHMkbp3h5W/2tFRxPL2C/Heqg==";
    };

    nativeBuildInputs = [
      autoPatchelfHook
      makeShellWrapper
      squashfsTools
    ];

    buildInputs = [
      alsa-lib
      dbus
      elfutils
      expat
      glib
      libGL
      libapparmor
      libbsd
      libedit
      libffi_3_3
      libgcrypt
      sqlite
      stdenv.cc.cc
      tcp_wrappers
      udev
      waylandpp
      xorg.libXinerama
      xz
      zstd
    ];

    strictDeps = true;

    unpackPhase = ''
      runHook preUnpack
      unsquashfs "$src"
      cd squashfs-root
      runHook postUnpack
    '';

    dontWrapQtApps = true;

    installPhase = ''
      runHook preInstall

      cp -r . $out

      ln -s ${libedit}/lib/libedit.so.0 $out/lib/libedit.so.2
      rm $out/usr/lib/x86_64-linux-gnu/libasound.so.2
      ln -s ${alsa-lib}/lib/libasound.so.2 $out/usr/lib/x86_64-linux-gnu/libasound.so.2
      rm $out/usr/lib/x86_64-linux-gnu/libasound.so.2.0.0
      ln -s ${alsa-lib}/lib/libasound.so.2.0.0 $out/usr/lib/x86_64-linux-gnu/libasound.so.2.0.0

      ln -snf ${glib.dev}/bin/gio-querymodules $out/usr/bin/gio-querymodules
      ln -snf ${glib.dev}/bin/glib-compile-schemas $out/usr/bin/glib-compile-schemas
      rm $out/usr/share/doc/libglib2.0-bin/changelog.Debian.gz
      rm $out/usr/share/doc/libxml2/NEWS.gz

      runHook postInstall
    '';
  };
in
buildFHSEnv {
  inherit pname version meta;
  targetPkgs = pkgs: [
    libdrm
    xkeyboard_config
  ];

  extraInstallCommands = ''
    mkdir -p $out/share/applications $out/share/icons/hicolor/scalable/apps
    install -m 444 -D ${plex-desktop}/meta/gui/plex-desktop.desktop $out/share/applications/plex-desktop.desktop
    substituteInPlace $out/share/applications/plex-desktop.desktop \
      --replace-fail \
      'Icon=''${SNAP}/meta/gui/icon.png' \
      'Icon=${plex-desktop}/meta/gui/icon.png'
  '';

  runScript = writeShellScript "plex-desktop.sh" ''
    # Widevine won't download unless this directory exists.
    mkdir -p $HOME/.cache/plex/

    # Copy the sqlite plugin database on first run.
    PLEX_DB="$HOME/.local/share/plex/Plex Media Server/Plug-in Support/Databases"
    if [[ ! -d "$PLEX_DB" ]]; then
      mkdir -p "$PLEX_DB"
      cp "${plex-desktop}/resources/com.plexapp.plugins.library.db" "$PLEX_DB"
    fi

    # db files should have write access.
    chmod --recursive 750 "$PLEX_DB"

    PLEX_USR_PATH=${lib.makeSearchPath "usr/lib/x86_64-linux-gnu" [ plex-desktop ]}

    set -o allexport
    LD_LIBRARY_PATH=${
      lib.makeLibraryPath [
        plex-desktop
        libglvnd-1_4_0
      ]
    }:$PLEX_USR_PATH
    LIBGL_DRIVERS_PATH=$PLEX_USR_PATH/dri
    ${lib.toShellVars extraEnv}
    exec ${plex-desktop}/Plex.sh
  '';
  passthru.updateScript = ./update.sh;
}
