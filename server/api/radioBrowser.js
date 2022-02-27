export const server = "https://fr1.api.radio-browser.info";

export const endpoints = {
  allStations: "/stations",
  clickCounter: "/url/{stationuuid}",
  countries: "/countries",
  codecs: "/codecs",
  tags: "/tags",
  byUUIDS: "/stations/byuuid{?uuids}",
  byName: "/stations/byname/{searchterm}",
  byExactName: "/stations/bynameexact/{searchterm}",
  byCodec: "/stations/bycodec/{searchterm}",
  byCodecExact: "/stations/bycodecexact/{searchterm}",
  byCountry: "/stations/bycountry/{searchterm}",
  byCountryExact: "/stations/bycountryexact/{searchterm}",
  byCountrycodeExact: "/stations/bycountrycodeexact/{searchterm}",
  byTag: "/stations/bytag/{searchterm}",
  byTagExact: "/stations/bytagexact/{searchterm}",
};
