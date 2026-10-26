{ ... }: {
  boot.loader = {
    efi.canTouchEfiVariables = true;
    limine = {
      enable = true;
      maxGenerations = 20;
      # 镜像/VM 不依赖 NVRAM，装到可移除路径更稳
      efiInstallAsRemovable = true;
    };
  };
  boot.kernelParams = [
    "quiet"
    "nowatchdog"
  ];
  zramSwap.enable = true;
}
