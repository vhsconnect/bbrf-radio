import ky from 'ky'
import { parse } from 'uri-template'
import { userAgent } from '../userAgent.mjs'

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
  byCountrycodeExact:
    '/stations/bycountrycodeexact/{searchterm}{?offset,limit}',
  byTag: '/stations/bytag/{searchterm}{?offset,limit}',
  byTagExact: '/stations/bytagexact/{searchterm}{?offset,limit}',
  servers: '/servers',
}

const mode = typeof window !== 'undefined' ? 'client' : 'server'

const request = ky.extend({
  headers: {
    'user-agent': `${userAgent} (${mode})`,
  },
})

export const radioApi = {
  getAllStations: server =>
    request(`https://${server}/json${endpoints.allStations}`).json(),

  getByTag: (server, tag, offset, limit) =>
    request(
      parse(`https://${server}/json${endpoints.byTagExact}`).expand({
        searchterm: tag,
        offset: offset * limit,
        limit: limit,
      })
    ).json(),

  getByCountryCode: (server, cc, offset, limit) =>
    request(
      parse(`https://${server}/json${endpoints.byCountrycodeExact}`).expand({
        searchterm: cc,
        offset: offset * limit,
        limit: limit,
      })
    ).json(),

  getByName: (server, name, offset, limit) =>
    request(
      parse(`https://${server}/json${endpoints.byName}`).expand({
        searchterm: name,
        offset: offset * limit,
        limit: limit,
      })
    ).json(),

  clickStation: (server, stationuuid) =>
    request(
      parse(`https://${server}/json${endpoints.clickCounter}`).expand({
        stationuuid: stationuuid,
      })
    ).json(),
}
