{
  description = "Hardened, self-contained mail server on NixOS for DigitalOcean";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Keep this branch in step with the nixpkgs release above.
    simple-nixos-mailserver = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver/nixos-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      simple-nixos-mailserver,
      disko,
      sops-nix,
    }:
    let
      inherit (nixpkgs) lib;

      mailLib = import ./lib { inherit lib; };

      mkMailServer =
        {
          settings,
          dkimDir,
          secretsFile,
          extraModules ? [ ],
        }:
        let
          ctx = mailLib.mkContext { inherit settings dkimDir secretsFile; };
        in
        {
          inherit ctx;
          system = lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit settings ctx; };
            modules = [
              disko.nixosModules.disko
              sops-nix.nixosModules.sops
              simple-nixos-mailserver.nixosModules.default
              ./modules/digitalocean.nix
              ./modules/hardening.nix
              ./modules/mail.nix
              ./modules/relay.nix
              ./modules/web.nix
              {
                networking.hostName = settings.hostname;
                networking.domain = settings.primaryDomain;
              }
            ]
            ++ extraModules;
          };
        };

      settings = import ./settings.nix;
      mail = mkMailServer {
        inherit settings;
        dkimDir = ./dkim;
        secretsFile = ./secrets/secrets.yaml;
        extraModules = [
          {
            assertions = [
              {
                assertion = builtins.pathExists ./secrets/secrets.yaml;
                message = "secrets/secrets.yaml does not exist. Run `just init` (and commit or `git add` the result).";
              }
            ];
          }
        ];
      };

      # A fixed configuration with test fixtures, so CI can build the modules
      # even before `just init` has created real keys.
      example = mkMailServer {
        settings = import ./tests/settings.nix;
        dkimDir = ./tests/dkim;
        secretsFile = ./tests/no-secrets.yaml;
      };

      devSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forDevSystems = f: lib.genAttrs devSystems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      nixosConfigurations.mail = mail.system;

      # Everything Terraform needs, derived from settings.nix and dkim/.
      # Exported by `just tfvars` to terraform/settings.auto.tfvars.json.
      tfvars = {
        inherit (settings) primaryDomain domains;
        inherit (mail.ctx) fqdn dnsRecords;
        hostname = settings.hostname;
        sshKeys = settings.sshKeys;
        sshAllowedCidrs = settings.sshAllowedCidrs;
        manageDns = settings.manageDns;
        droplet = settings.droplet;
      };

      devShells = forDevSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            just
            opentofu
            sops
            age
            ssh-to-age
            openssl
            openssh
            mkpasswd
            jq
            dig
            nixos-anywhere
            nixos-rebuild-ng
            nixfmt
          ];
        };
      });

      formatter = forDevSystems (pkgs: pkgs.nixfmt-tree);

      # Build the complete system closure: catches option typos, failed
      # assertions and broken packages before anything reaches the server.
      # `system` only exists once `just init` has created the secrets.
      checks.x86_64-linux = {
        example = example.system.config.system.build.toplevel;
      }
      // lib.optionalAttrs (builtins.pathExists ./secrets/secrets.yaml) {
        system = self.nixosConfigurations.mail.config.system.build.toplevel;
      };
    };
}
