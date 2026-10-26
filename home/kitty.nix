{ ... }: {
  xdg.configFile = {
    "kitty/kitty.conf".source = ./files/kitty/kitty.conf;
    "kitty/__custom__.conf".source = ./files/kitty/__custom__.conf;
    "kitty/themes/noctalia.conf".source = ./files/kitty/themes/noctalia.conf;
  };
}
