{ pkgs, lib, symlinkJoin, makeWrapper
, hpack, git, nix, nix-prefetch-git
, fetchExternal, cleanSourceHaskell, mkCabalProjectPkgSet }:

let
  src = cleanSourceHaskell (fetchExternal {
    name     = "nix-tools-src";
    specJSON = ./nix-tools-src.json;
    override = "nix-tools-src";
  });
  # we need to patch Cabal, as its data directory logic is broken for component builds, which haskell.nix
  # uses excessively. See issue https://github.com/haskell/cabal/issues/5862, and the fix for Cabal 3.0
  # in https://github.com/haskell/cabal/pull/6055. We apply the haskell/cabal#6055 here.
  cabalPatch = pkgs.fetchpatch {
    url = "https://patch-diff.githubusercontent.com/raw/haskell/cabal/pull/6055.diff";
    sha256 = "145g7s3z9q8d18pxgyngvixgsm6gmwh1rgkzkhacy4krqiq0qyvx";
    stripLen = 1;
  };

  pkgSet = mkCabalProjectPkgSet {
    plan-pkgs = import ./pkgs.nix;
    pkg-def-extras = [];
    modules = [
      {
        packages.transformers-compat.components.library.doExactConfig = true;
        packages.time-compat.components.library.doExactConfig = true;
        packages.time-locale-compat.components.library.doExactConfig = true;
      }

      {
        packages.nix-tools.src = src;
      }

      ({ config, ...}: {
        packages = {
          Cabal.patches = [ cabalPatch ];
        };
      })
    ];
  };

  hsPkgs = pkgSet.config.hsPkgs;

  tools = [ hpack git nix nix-prefetch-git ];
in
  symlinkJoin {
    name = "nix-tools";
    paths = builtins.attrValues hsPkgs.nix-tools.components.exes;
    buildInputs = [ makeWrapper ];
    postBuild = ''
      for prog in stack-to-nix cabal-to-nix plan-to-nix; do
        wrapProgram "$out/bin/$prog" --prefix PATH : "${lib.makeBinPath tools}"
      done
    '';
  }
