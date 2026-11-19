{pkgs, listen}: {
  name = "llama-swap";
  comment = "Open the local llama-swap web interface";
  exec = "${pkgs.xdg-utils}/bin/xdg-open http://${listen}/ui/";
  icon = "web-browser";
  categories = ["Development"];
}
