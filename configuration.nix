# configuration.nix
{ config, pkgs, lib, ... }:

{
  imports = [ 
    ./hardware-configuration.nix
  ];

  # Boot loader configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Basic system configuration
  system.stateVersion = "23.11";

  # Enable Flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Create www-data user and group
  users.users.www-data = {
    isSystemUser = true;
    group = "www-data";
    uid = 33;  # Standard www-data UID
  };
  users.groups.www-data = {
    gid = 33;  # Standard www-data GID
  };

  # User configuration
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "networkmanager" "www-data" ];
    initialPassword = "changeme";
  };

  # Create docker group
  users.groups.docker = {};

  # Updated networking configuration
  networking = {
    hostName = "groupoffice";
    networkmanager.enable = true;
    useDHCP = lib.mkDefault true;
    
    # Basic firewall configuration
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 9000 3306 ]; # SSH, GroupOffice, and MariaDB
    };
  };

  # Disable the wait-online service directly
  systemd.services."NetworkManager-wait-online".enable = false;

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

  # Directory structure for GroupOffice with correct permissions
  systemd.tmpfiles.rules = [
    # Base directories with execute permissions
    "d /usr/local/share/groupoffice 0755 www-data www-data -"
    "d /usr/local/share/groupoffice/install 0755 www-data www-data -"
    
    # Data directories
    "d /var/lib/groupoffice 0755 www-data www-data -"
    "d /var/lib/groupoffice/data 0755 www-data www-data -"
    "d /var/lib/groupoffice/config 0755 www-data www-data -"
    "d /var/lib/groupoffice/mariadb 0755 www-data www-data -"
    "d /var/lib/groupoffice/tmp 1777 www-data www-data -"
    
    # Config directory
    "d /etc/groupoffice 0755 www-data www-data -"
    "f /etc/groupoffice/config.php 0644 www-data www-data -"
  ];

  # Ensure directories exist and have correct permissions
  system.activationScripts.groupoffice-dirs = {
    text = ''
      mkdir -p /usr/local/share/groupoffice
      mkdir -p /var/lib/groupoffice
      mkdir -p /etc/groupoffice
      chown -R www-data:www-data /usr/local/share/groupoffice
      chown -R www-data:www-data /var/lib/groupoffice
      chown -R www-data:www-data /etc/groupoffice
      chmod -R 755 /usr/local/share/groupoffice
      chmod -R 755 /var/lib/groupoffice
      chmod -R 755 /etc/groupoffice
    '';
  };

  # Cron job for GroupOffice
  services.cron = {
    enable = true;
    systemCronJobs = [
      "* * * * * www-data docker exec groupoffice php /usr/local/share/groupoffice/cron.php"
    ];
  };

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
          MYSQL_HOST = "db";
          MYSQL_DATABASE = "groupoffice";
          MYSQL_USER = "groupoffice";
          MYSQL_PASSWORD = "groupoffice";
          PHP_UPLOAD_MAX_FILESIZE = "128M";
          PHP_POST_MAX_SIZE = "128M";
          PHP_MEMORY_LIMIT = "512M";
          APACHE_RUN_USER = "www-data";
          APACHE_RUN_GROUP = "www-data";
          DEBUG = "1";
        };
        volumes = [
          "/usr/local/share/groupoffice:/usr/local/share/groupoffice"
          "/var/lib/groupoffice:/var/lib/groupoffice"
          "/etc/groupoffice:/etc/groupoffice"
        ];
        extraOptions = [
          "--network=proxy-network"
          "--user=33:33"
        ];
        dependsOn = [ "db" ];
      };

      db = {
        image = "mariadb:11.5.2";
        autoStart = true;
        ports = [ "3306:3306" ];
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

  # Docker network service
  systemd.services.create-docker-network = {
    description = "Create docker network for GroupOffice";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
    };
    script = ''
      # Wait for Docker to be ready
      for i in {1..30}; do
        if ${pkgs.docker}/bin/docker info >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done
      
      # Create network if it doesn't exist
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
    tailscale
  ];
}