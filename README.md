# BBRF - Barebones radio with a fader

BBRF radio is a a lightweight downstream client to the delightful [radio-browser](https://de1.api.radio-browser.info/) api - a hosted service that serves metadata on all openly available online radios. You can run bbrf as a self-hosted stateful server or client only through [bbrf.vhsconnect.link](https://bbrf.vhsconnect.link)

## Client only

Use this to test the server or for using bbrf as a radio bookmarking tool with a convenience media player. For most people this is the way to go. The app is stateless, all your favorites will be saved through the url - so you'll need to re-bookmark the url everytime you add or remove a favorite. The limitation hre is the 4096 character limit in the url. So expect the site to stop loading after 12 - 15 favorites more or less. If you're using your phone and bookmarking the app a firefox/chromium shortcut - you can create various shortcuts for different types of radio (News, Classical, World, etc...) - that's what I do.


## Server

To get started, Start up the server, or better yet host it on your network's raspberry pi or set it up as a `systemd`/`launchd` service. The app is served on port `3335` to be accessed on your browser.


### Quick start

- Build the app `npm run build`
- Start the service `npm run start`
- Run the development server `npm run dev`
- Optionaly add some radio stations to your favs list `npm run defaults`
- Default port to access the application is on localhost:3335
- You can also alias the bbrf server for easy scripting `npm link`
- You can change the binding port, or the fader value by updating/creating your `$XDG_CONFIG_HOME/bbrf-radio/settings` file.

```json
{ "FADER_VALUE": 25, "PORT": 5555, "ITEM_PER_PAGE": 2000 }
```

### Try out the project

[![Try with Replit Badge](https://replit.com/badge?caption=Try%20with%20Replit)](https://replit.com/github/vhsconnect/bbrf-radio)

### Usage with nixos

This repo exposes a nix module as part of a flake. You can import it as one of your inputs if you use flakes to configure your system (systemd module on NixOs or launchd module on Mac). Otherwise you can just use the package exported as a standalone script that you can invoke in your own systemd module or however else.

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
    itemsPerPage = 2000; #Upper limit is 100000
  };

}

```

### Contributing

You can run the application in development mode.

```bash
npm run dev
```
