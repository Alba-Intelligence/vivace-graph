{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
{

languages = {
    elixir = {enable = true; lsp.enable = true;};
  };

  # Environment variables
  env = {
    GREET = "devenv";
    LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath (
      with pkgs;
      [
        openssl_legacy
        openssl_oqs
        openssl_3_5
        openssl_3_6
      ]
    )}";
  };

  # https://devenv.sh/packages/
  packages = (
    with pkgs;
    [
      git
      openssl_oqs
      openssl_3_5
      openssl_3_6
      openssl_legacy

      # Basic utilities
      ripgrep # Text search utility
      hexdump # Hexadecimal dump utility
      jq # JSON processor
      xxd # Hexadecimal editor

      sbcl
      ecl
      ccl

      zlib-ng # Streaming of compressed Turtle files
    ]
  );


  enterShell = ''
    echo
  '';

  enterTest = "";
}
