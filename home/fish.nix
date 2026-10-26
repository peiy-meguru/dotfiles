{ pkgs, ... }: {
  programs.fish = {
    enable = true;
    shellAliases = {
      ls = "eza --icons=auto";
      ll = "eza -l --icons=auto";
      la = "eza -la --icons=auto";
      lt = "eza --tree --level=2 --icons=auto";
      grep = "rg";
      cat = "bat";
      clear = "printf '\\033[2J\\033[3J\\033[1;1H'";
    };
    interactiveShellInit = ''
      set fish_greeting
    '';
    functions = {
      proxy_on = ''
        set -gx http_proxy "http://127.0.0.1:7890"
        set -gx https_proxy "http://127.0.0.1:7890"
        set -gx all_proxy "socks5://127.0.0.1:7890"
        set -gx HTTP_PROXY $http_proxy
        set -gx HTTPS_PROXY $https_proxy
        set -gx ALL_PROXY $all_proxy
        echo "[+] 代理已开启 (127.0.0.1:7890)"
      '';
      proxy_off = ''
        set -e http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
        echo "[-] 代理已关闭"
      '';
      proxy_status = ''
        for var in http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
          if set -q $var
            echo "$var: "$$var
          else
            echo "$var: [未设置]"
          end
        end
      '';
    };
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    settings = builtins.fromTOML (builtins.readFile ./files/starship.toml);
  };

  programs.bat.enable = true;
  programs.eza.enable = true;
  programs.fzf.enable = true;
  programs.fzf.enableFishIntegration = true;
}
