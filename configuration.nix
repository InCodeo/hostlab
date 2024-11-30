# configuration.nix

{ config, pkgs, ... }:

{
  # Basic system configuration
  system.stateVersion = "23.11";

  # Enable Flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # User configuration
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "networkmanager" ];
    initialPassword = "changeme";
  };

  # Create docker group
  users.groups.docker = {};

  # Basic networking
  networking = {
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 9000 ]; # SSH and GroupOffice
    };
    # Enable Tailscale
    networkmanager.enable = true;
  };

  # Enable SSH
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = false;
  };

  # Enable Tailscale
  services.tailscale.enable = true;

  # Docker configuration
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  # Directory structure for GroupOffice
  systemd.tmpfiles.rules = [
    "d /var/lib/groupoffice 0750 admin docker -"
    "d /var/lib/groupoffice/data 0750 admin docker -"
    "d /var/lib/groupoffice/config 0750 admin docker -"
    "d /var/lib/groupoffice/mariadb 0750 admin docker -"
  ];

  # Container configurations
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      groupoffice = {
        image = "intermesh/groupoffice:6.8";
        autoStart = true;
        ports = [ "9000:80" ];
        environment = {
          TZ = "Australia/Sydney";
          MYSQL_USER = "groupoffice";
          MYSQL_PASSWORD = "groupoffice";
          MYSQL_DATABASE = "groupoffice";
          MYSQL_HOST = "db";
        };
        volumes = [
          "/var/lib/groupoffice/data:/var/lib/groupoffice"
          "/var/lib/groupoffice/config:/etc/groupoffice"
        ];
        extraOptions = [
          "--network=proxy-network"
        ];
        dependsOn = [ "groupoffice-db" ];
      };

      groupoffice-db = {
        image = "mariadb:11.1.2";
        autoStart = true;
        environment = {
          TZ = "Australia/Sydney";
          MYSQL_ROOT_PASSWORD = "groupoffice";
          MYSQL_USER = "groupoffice";
          MYSQL_PASSWORD = "groupoffice";
          MYSQL_DATABASE = "groupoffice";
          MARIADB_AUTO_UPGRADE = "1";
        };
        volumes = [
          "/var/lib/groupoffice/mariadb:/var/lib/mysql"
        ];
        extraOptions = [
          "--network=proxy-network"
        ];
      };
    };
  };

  # Create docker network on system startup
  systemd.services.create-docker-network = {
    description = "Create docker network for GroupOffice";
    after = [ "network.target" "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Check if network exists
      if ! ${pkgs.docker}/bin/docker network inspect proxy-network >/dev/null 2>&1; then
        ${pkgs.docker}/bin/docker network create proxy-network
      fi
    '';
  };

  # System Packages
  environment.systemPackages = with pkgs; [
    docker
    docker-compose
    git
    htop
    vim
  ];
}