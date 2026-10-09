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
          machineFile,
          extraModules ? [ ],
        }:
        let
          ctx = mailLib.mkContext {
            inherit
              settings
              dkimDir
              secretsFile
              machineFile
              ;
          };
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
              ./modules/machine.nix
              ./providers/${settings.provider}.nix
              ./modules/hardening.nix
              ./modules/mail.nix
              ./modules/relay.nix
              ./modules/web.nix
              ./modules/backup.nix
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
        machineFile = ./machine.json;
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

      # Fixed configurations with test fixtures, one per provider, so CI can
      # build the modules even before `just init` has created real keys.
      examples = lib.genAttrs (lib.attrNames (import ./lib/providers.nix)) (
        provider:
        mkMailServer {
          settings = import ./tests/settings.nix // {
            inherit provider;
          };
          dkimDir = ./tests/dkim;
          secretsFile = ./tests/no-secrets.yaml;
          machineFile = ./tests/machine.json;
        }
      );

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
      # Written by `just apply` to infra/*/settings.auto.tfvars.json.
      tfvars = {
        inherit (settings)
          hostname
          primaryDomain
          domains
          sshKeys
          sshAllowedCidrs
          provider
          dns
          ;
        inherit (mail.ctx) fqdn dnsRecords;
        server = settings.server.${settings.provider};
        providerInfo = mail.ctx.provider;
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
            curl
            restic
            # OVHcloud: reinstalls a newly ordered VPS with your SSH key
            (python3.withPackages (ps: [ ps.ovh ]))
          ];
        };
      });

      formatter = forDevSystems (pkgs: pkgs.nixfmt-tree);

      # Build the complete system closure: catches option typos, failed
      # assertions and broken packages before anything reaches the server.
      # `system` only exists once `just init` has created the secrets and
      # `just install` has recorded machine.json.
      checks.x86_64-linux =
        lib.mapAttrs' (
          provider: example:
          lib.nameValuePair "example-${provider}" example.system.config.system.build.toplevel
        ) examples
        //
          lib.optionalAttrs (builtins.pathExists ./secrets/secrets.yaml && builtins.pathExists ./machine.json)
            {
              system = self.nixosConfigurations.mail.config.system.build.toplevel;
            };
    };
}
