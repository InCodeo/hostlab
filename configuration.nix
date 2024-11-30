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

  # User configuration
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "networkmanager" ];
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
    settings.PermitRootLogin = "yes";
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
    "d /usr/local/share/groupoffice 0755 root root -"
    "d /var/lib/groupoffice 0755 root root -"
    "d /var/lib/groupoffice/data 0755 root root -"
    "d /var/lib/groupoffice/config 0755 root root -"
    "d /var/lib/groupoffice/mariadb 0755 root root -"
    "d /var/lib/groupoffice/tmp 1777 root root -"
    "d /etc/groupoffice 0755 root root -"
  ];

  # Create initial config.php file
  system.activationScripts.groupoffice-config = {
    text = ''
      mkdir -p /etc/groupoffice
      cat > /etc/groupoffice/config.php << 'EOF'
<?php
$config['db_name'] = 'groupoffice';
$config['db_host'] = 'db';
$config['db_user'] = 'groupoffice';
$config['db_pass'] = 'groupoffice';
$config['db_port'] = 3306;
$config['file_storage_path'] = '/var/lib/groupoffice';
$config['tmpdir'] = '/tmp/groupoffice';
$config['debug'] = true;
EOF
      chmod 644 /etc/groupoffice/config.php
    '';
  };

  # Cron job for GroupOffice
  services.cron = {
    enable = true;
    systemCronJobs = [
      "* * * * * root docker exec groupoffice php /usr/local/share/groupoffice/cron.php"
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
          GO_CONFIG_DATABASE_HOST = "db";
          GO_CONFIG_DATABASE_NAME = "groupoffice";
          GO_CONFIG_DATABASE_USER = "groupoffice";
          GO_CONFIG_DATABASE_PASSWORD = "groupoffice";
          PHP_UPLOAD_MAX_FILESIZE = "128M";
          PHP_POST_MAX_SIZE = "128M";
          PHP_MEMORY_LIMIT = "512M";
        };
        volumes = [
          "/var/lib/groupoffice/data:/var/lib/groupoffice"
          "/etc/groupoffice:/etc/groupoffice"
          "/var/lib/groupoffice/tmp:/tmp/groupoffice"
        ];
        extraOptions = [
          "--network=proxy-network"
        ];
        dependsOn = [ "db" ];
      };

      db = {
        image = "mariadb:11.5.2";
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