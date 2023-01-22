# BBRF - Barebones radio with a fader

_BBRF is still a work in progress_

BBRF radio is a lightweight self-hosted service and frontend to interface with the open [radio-browser](https://de1.api.radio-browser.info/) api - a hosted service that serves metadata on all openly available online radios. To get started, Start up the server, or better yet host it on your network's raspberry pi or set it up as a `systemd`/`launchd` service. The app is served on port `3335` to be accessed on your browser.

### Quick start with some curated radios

```bash
yarn run defaults
```

### Start the service

```bash
yarn run start
```

then access on localhost:3335

### Alias the server executable globally

```bash
yarn run build #build first
yarn link
```

then call it - `bbrf-radio`

### Usage with nixos

This repo exposes a nix module as part of a flake. You can import it as one of your inputs if you use flakes to configure your system.

```nix
{
  # your inputs
  #...
  inputs =
    {
      #...
      bbrf = "github:vhsconnect/bbrf-radio/master";
    };

  # then import it as one your modules
  outputs = inputs: {
    nixosConfigurations = {
      mySystem = inputs.nixpkgs.lib.nixosSystem {
        #...
        modules = [
          #...
          inputs.bbrf.nixosModules.${builtins.currentSystem}.bbrf
        ];
      };
    };
  };
}

```

then in your configuration activate it with the settings you prefer
```nix
{
  services.bbrf =  {
    enable = true;
    port = 3111;
    user = "username";
    fadeValue = 40; # how fast to fade between radios
  };

}

```



### Contributing
You can run the application in development mode.

```bash
yarn run dev
```
