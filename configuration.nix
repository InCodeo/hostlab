{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking configuration
  networking = {
    hostName = "nixos-manager";
    useDHCP = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 
        22    # SSH
        53    # DNS (AdGuard)
        80    # HTTP (NPM)
        81    # NPM Admin Portal
        443   # HTTPS (NPM)
        3000  # AdGuard Home Admin
        3150  # Homepage Dashboard (direct access)
        3306  # MariaDB
        8000  # Test HTTP Server
        9000  # Portainer
      ];
      allowedUDPPorts = [ 
        config.services.tailscale.port
        53    # DNS
      ];
      trustedInterfaces = [ "tailscale0" ];
    };
  };

  # Docker and Container Configuration
  virtualisation = {
    docker = {
      enable = true;
      enableOnBoot = true;
      package = pkgs.docker;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };
    oci-containers = {
      backend = "docker";
      containers = {
        portainer = {
          image = "portainer/portainer-ce:latest";
          volumes = [
            "/var/run/docker.sock:/var/run/docker.sock"
            "/var/lib/portainer/data:/data"
          ];
          environment = {
            TZ = "Australia/Sydney";
          };
          ports = ["9000:9000"];
          extraOptions = [
            "--network=proxy-network"
          ];
          autoStart = true;
        };
        
        homepage = {
          image = "ghcr.io/gethomepage/homepage:latest";
          ports = [ "3150:3000" ];
          environment = {
            PUID = "1001";
            PGID = "131";
            DEBUG = "true";
          };
          volumes = [
            "/var/lib/homepage/config:/app/config"
            "/var/run/docker.sock:/var/run/docker.sock:ro"
          ];
          extraOptions = [
            "--network=proxy-network"
          ];
          autoStart = true;
        };

        npm = {
          image = "jc21/nginx-proxy-manager:latest";
          ports = [
            "80:80"
            "81:81"
            "443:443"
          ];
          environment = {
            DISABLE_IPV6 = "true";
            TZ = "Australia/Sydney";
          };
          volumes = [
            "/var/lib/npm/data:/data"
            "/var/lib/npm/letsencrypt:/etc/letsencrypt"
          ];
          extraOptions = [
            "--network=proxy-network"
          ];
          autoStart = true;
        };
      };
    };
  };

  # AdGuard Home configuration
  services.adguardhome = {
    enable = true;
    host = "0.0.0.0";
    port = 3000;
    mutableSettings = false;
    
    settings = {
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        bootstrap_dns = [
          "8.8.8.8"
          "1.1.1.1"
        ];
        upstream_dns = [
          "8.8.8.8"
          "1.1.1.1"
        ];
        local_domain_name = "home";
        resolve_clients = true;
        rewrites = [
          {
            domain = "my.home";
            answer = "100.113.131.93";
          }
          {
            domain = "npm.home";
            answer = "100.113.131.93";
          }
          {
            domain = "adguard.home";
            answer = "100.113.131.93";
          }
        ];
      };
      http = {
        username = "admin";
        password = ""; # Add your password hash here
      };
      filters = [];
      user_rules = [];
      schema_version = 12;
    };
  };

  # Create Docker network and directories
  systemd.services.docker-network-setup = {
    description = "Create Docker network and set up directories";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Create the network if it doesn't exist
      if ! docker network inspect proxy-network >/dev/null 2>&1; then
        docker network create proxy-network
      fi
    '';
    wantedBy = [ "multi-user.target" ];
    requires = [ "docker.service" ];
    after = [ "docker.service" ];
  };

  # Directory Structure
  systemd.tmpfiles.rules = [
    "d /var/lib/portainer 0750 admin docker -"
    "d /var/lib/portainer/data 0750 admin docker -"
    "d /var/lib/npm 0750 admin docker -"
    "d /var/lib/npm/data 0750 admin docker -"
    "d /var/lib/npm/mysql 0750 admin docker -"
    "d /var/lib/npm/letsencrypt 0750 admin docker -"
    "d /var/lib/www/test 0755 admin admin -"
    "d /var/lib/homepage 0755 admin docker -"
    "d /var/lib/homepage/config 0755 admin docker -"
  ];

  # User Configuration
  users.users.admin = {
    isNormalUser = true;
    description = "Management Admin";
    extraGroups = [ "wheel" "docker" ];
    initialPassword = "changeme";
  };

  # Shell Configuration
  programs.zsh = {
    enable = true;
    ohMyZsh = {
      enable = true;
      plugins = [ "git" "docker" "sudo" ];
      theme = "robbyrussell";
    };
    shellInit = ''
      ${builtins.replaceStrings ["\r\n"] ["\n"] (builtins.readFile ./functions.zsh)}
      ${builtins.replaceStrings ["\r\n"] ["\n"] (builtins.readFile ./client-functions.zsh)}
    '';
  };

  users.defaultUserShell = pkgs.zsh;
  users.users.root.shell = pkgs.zsh;

  # System Packages
  environment.systemPackages = with pkgs; [
    # Core utilities
    wget vim git curl
    
    # Network tools
    tailscale
    bind        # for dig/nslookup
    inetutils   # for ping, etc.
    
    # System monitoring
    htop tmux
    
    # Shell
    zsh oh-my-zsh

    # Added for test server
    python3
  ];

  # Enable Tailscale
  services.tailscale.enable = true;

  # Kernel Parameters
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "fs.inotify.max_user_watches" = 524288;
    "net.core.somaxconn" = 65535;
  };

  # SSH Configuration
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;  # Will be disabled after initial setup
      PermitRootLogin = "yes";       # Will be disabled after initial setup
      X11Forwarding = false;
      PermitEmptyPasswords = false;
      MaxAuthTries = 3;
    };
  };

  system.stateVersion = "24.05";
}