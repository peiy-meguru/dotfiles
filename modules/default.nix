{ ... }: {
  imports = [
    ./base.nix
    ./boot.nix
    ./desktop.nix
    ./input-method.nix
    ./fonts.nix
    ./packages.nix
    ./services.nix
    ./home-manager.nix
    ./nvidia-patchelf-fix.nix
    ./greeter.nix
    ./windows-pointer.nix
  ];
}
