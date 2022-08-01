# BBRF - Barebones radio with fader

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


### Contributing

```bash
yarn run dev
```

