{ config, pkgs, lib, ... }:  
{
    networking.networkmanager.enable = true;

    networking.hostName = "spyro-nv_plasma"; # Define your hostname.
    networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant. 

    # Configure network proxy if necessary
    #networking.proxy.default = "http://user:password@proxy:port/";
    #networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";


    # Open ports in the firewall.
    #networking.firewall.allowedTCPPorts = [ 47989 47990 47998 47999 ];
    #networking.firewall.allowedUDPPorts = [ 47989 47990 47998 47999 ];
    # Or disable the firewall altogether.
    #networking.firewall.enable = false;
}