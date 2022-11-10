export const mainServer = 'https://de1.api.radio-browser.info'

export  const radioBrowserMirrors = [
      'https://de1.api.radio-browser.info',
      'https://nl1.api.radio-browser.info',
      'https://fr1.api.radio-browser.info',
] 

export const endpoints = {
  allStations: '/stations',
  clickCounter: '/url/{stationuuid}',
  countries: '/countries',
  codecs: '/codecs',
  tags: '/tags',
  byUUIDS: '/stations/byuuid{?uuids}',
  byName: '/stations/byname/{searchterm}{?offset,limit}',
  byExactName: '/stations/bynameexact/{searchterm}{?offset,limit}',
  byCodec: '/stations/bycodec/{searchterm}',
  byCodecExact: '/stations/bycodecexact/{searchterm}',
  byCountry: '/stations/bycountry/{searchterm}{?offset,limit}',
  byCountryExact: '/stations/bycountryexact/{searchterm}{?offset,limit}',
  byCountrycodeExact: '/stations/bycountrycodeexact/{searchterm}{?offset,limit}',
  byTag: '/stations/bytag/{searchterm}{?offset,limit}',
  byTagExact: '/stations/bytagexact/{searchterm}{?offset,limit}',
  servers: '/servers'
}
