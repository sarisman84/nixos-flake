{ pkgs, inputs, ... }: {

  environment.systemPackages = [
    inputs.nuhxboard.packages.${pkgs.system}.default
  ];

}
