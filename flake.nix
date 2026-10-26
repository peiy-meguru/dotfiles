{
  description = "NixOS Configuration File";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      disko,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (nixpkgs) lib;

      # 管线：把外部项目加工成本仓库可直接消费的产物。
      # 见 pipeline/default.nix 与 README「架构」一节。
      # 管线：非 nixpkgs 项目的处理。
      # Nyxuri 已物化到 vendor/（见 pipeline/materialize.sh），
      # 所以这里不需要任何外部 flake 输入 —— 干净 clone 就能从 0 构建。
      pipeline = import ./pipeline { inherit pkgs lib; };

      mkHost =
        hostName:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs hostName pipeline; };
          modules = [
            disko.nixosModules.disko
            home-manager.nixosModules.home-manager
            ./modules
            ./hosts/${hostName}
          ];
        };

      # 新增机器：在 hosts/<name>/ 建目录，再把名字加进这个列表
      hostNames = [
        "username"
        "username-vm"
      ];
    in
    {
      nixosConfigurations = lib.genAttrs hostNames mkHost;

      # `nix fmt` —— 全仓库统一用 nixfmt-rfc-style
      formatter.${system} = pkgs.nixfmt-rfc-style;

      # ── `nix flake check` ──────────────────────────────────────────
      # 只放「轻量静态检查」：格式、shell、Lua 语法。
      # 配置本身能不能求值、能不能构建，交给 CI 里的
      # `nix eval` / `nix build` 显式做（见 .github/workflows/ci.yml），
      # 因为把整机闭包塞进 checks 会拖入内核/NVIDIA 的编译。
      # 本地也能跑：nix flake check
      checks.${system} = {
        # 所有 .nix 文件必须 nixfmt 干净（`nix fmt` 自动修）
        formatting =
          pkgs.runCommand "check-formatting"
            {
              nativeBuildInputs = [ pkgs.nixfmt-rfc-style ];
            }
            ''
              cd ${self}
              nixfmt --check $(find . -name '*.nix' -not -path './.git/*')
              touch $out
            '';

        # 入库的 shell 脚本只有 pipeline/materialize.sh，检查它
        shellcheck =
          pkgs.runCommand "check-shellcheck"
            {
              nativeBuildInputs = [ pkgs.shellcheck ];
            }
            ''
              shellcheck -S warning ${self}/pipeline/materialize.sh
              touch $out
            '';

        # libinput 插件（engine + adapter）的 Lua 语法
        lua-syntax =
          pkgs.runCommand "check-lua-syntax"
            {
              nativeBuildInputs = [ pkgs.lua5_4 ];
            }
            ''
              for f in ${self}/pipeline/windows-pointer/*.lua; do
                lua -e "assert(loadfile('$f'))"
              done
              touch $out
            '';
      };
    };
}
