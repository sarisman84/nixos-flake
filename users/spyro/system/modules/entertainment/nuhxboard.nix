{ pkgs, inputs, ... }: {
  imports = [
    inputs.nuhxboard
  ];

environment.systemPackages = with pkgs;  [
  packages.${system}.nuhxboard
  packages.${system}.default
];


}
