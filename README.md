# BBRF - Barebones radio with a fader


BBRF radio is a lightweight self-hosted service and frontend to interface with the open [radio-browser](https://de1.api.radio-browser.info/) api - a hosted service that serves metadata on all openly available online radios. To get started, Start up the server, or better yet host it on your network's raspberry pi or set it up as a `systemd`/`launchd` service. The app is served on port `3335` to be accessed on your browser.

## Note about broken upstream.

One of the query endpoints is broken upstream. this results in the favorites feature not working. As a workaround you can use this branch feature/server-refresh-with-upfix. You'll just need to remove your favorites files in `.XDG_CONFIG_HOME/bbrf-radio/storage.json`. Otherwise just hold tight until upsteam is fixed.

### Quick start

- Build the app `npm run build`
- Start the service `npm run start`
- Run the development server `npm run dev`
- Optionaly add some radio stations to your favs list `npm run defaults`
- Default port to access the application is on localhost:3335
- You can also alias the bbrf server for easy scripting `npm link`
- You can change the binding port, or the fader value by updating/creating your `$XDG_CONFIG_HOME/bbrf-radio/settings` file.

```json
{ "FADER_VALUE": 25, "PORT": 5555 }
```

### Try out the project

[![Try with Replit Badge](https://replit.com/badge?caption=Try%20with%20Replit)](https://replit.com/github/vhsconnect/bbrf-radio)

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
npm run dev
```
