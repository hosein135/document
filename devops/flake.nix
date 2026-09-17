{
  description = "مدار منطقی Typst document (typst 0.13.1 + parastoo-fonts, nixos-25.05)";

  nixConfig = {
    extra-substituters = [ "https://cache.nixos.org" ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkPkgs = system: import nixpkgs { inherit system; };

      fontDir = pkgs: "${pkgs.parastoo-fonts}/share/fonts/parastoo-fonts";

      compileScript =
        pkgs:
        pkgs.writeShellApplication {
          name = "compile-madar-manteghi";
          runtimeInputs = [
            pkgs.typst
            pkgs.coreutils
          ];
          text = ''
            set -euo pipefail
            root="''${LOGIC_DOC_ROOT:-$(pwd)}"
            if [ ! -f "$root/src/main.typ" ] && [ -f "$root/../src/main.typ" ]; then
              root="$(cd "$root/.." && pwd)"
            fi
            src="$root/src/main.typ"
            out_dir="$root/output"
            out_pdf="$out_dir/madar-manteghi.pdf"
            font_dir="${fontDir pkgs}"

            if [ ! -f "$src" ]; then
              echo "missing Typst source: $src" >&2
              exit 1
            fi
            mkdir -p "$out_dir"
            export TYPST_FONT_PATHS="$font_dir"
            echo "==> typst $(typst --version)"
            echo "==> fonts  $TYPST_FONT_PATHS"
            typst compile \
              --root "$root" \
              --font-path "$font_dir" \
              --ignore-system-fonts \
              "$src" \
              "$out_pdf"
            echo "==> wrote $out_pdf"
          '';
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          pdf = pkgs.stdenvNoCC.mkDerivation {
            pname = "madar-manteghi";
            version = "1.0.0";
            src = ../src;
            nativeBuildInputs = [ pkgs.typst ];
            env.TYPST_FONT_PATHS = fontDir pkgs;
            buildPhase = ''
              runHook preBuild
              typst compile \
                --font-path "$TYPST_FONT_PATHS" \
                --ignore-system-fonts \
                main.typ \
                madar-manteghi.pdf
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p $out
              cp madar-manteghi.pdf $out/
              runHook postInstall
            '';
          };
        in
        {
          default = pdf;
          pdf = pdf;
          compile = compileScript pkgs;
        }
      );

      apps = forAllSystems (
        system:
        let
          compile = self.packages.${system}.compile;
        in
        {
          default = {
            type = "app";
            program = "${compile}/bin/compile-madar-manteghi";
          };
          compile = {
            type = "app";
            program = "${compile}/bin/compile-madar-manteghi";
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          default = pkgs.mkShell {
            name = "madar-manteghi";
            packages = [
              pkgs.typst
              pkgs.parastoo-fonts
              pkgs.curl
            ];
            TYPST_FONT_PATHS = fontDir pkgs;
            shellHook = ''
              export LOGIC_DOC_ROOT="''${LOGIC_DOC_ROOT:-$PWD}"
              export TYPST_FONT_PATHS="${fontDir pkgs}"
              echo "devShell (nixos-25.05): typst $(typst --version 2>/dev/null || true)"
              echo "Parastoo fonts: $TYPST_FONT_PATHS"
              echo "Compile: ./run.sh   or   nix run ./devops#compile"
            '';
          };
        }
      );
    };
}
