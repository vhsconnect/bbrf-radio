import { Schema } from 'effect'
import { TracklistingSchema } from '../types'

const jazzStation = {
  stationuuid: 'stub-station-1',
  name: 'Example Jazz FM',
  url: 'http://example.com:8000/jazz',
  url_resolved: 'http://example.com:8000/jazz',
  countrycode: 'SE',
  bitrate: 128,
  tags: 'jazz, bebop,soul',
} as const

const rockStation = {
  stationuuid: 'stub-station-2',
  name: 'Another Rock Radio',
  url: 'http://example.com:8000/rock',
  url_resolved: 'http://example.com:8000/rock',
  countrycode: 'DE',
  bitrate: 192,
  tags: 'rock,classic rock',
} as const

const talkStation = {
  stationuuid: 'stub-station-3',
  name: 'Example Talk',
  url: 'http://example.com:8000/talk',
  url_resolved: 'http://example.com:8000/talk',
  countrycode: 'GB',
  bitrate: 64,
  tags: 'talk,news',
} as const

const tracklisting = [
  {
    id: 8,
    station: jazzStation,
    observed_at: '2026-10-22T21:42:00.000000Z',
    raw_title: 'John  ',
    artist: 'John ',
    title: 'Naima',
  },
  {
    id: 7,
    station: rockStation,
    observed_at: '2026-10-22T21:39:00.000000Z',
    raw_title: 'Led Zeppelin - Kashmir',
    artist: 'Led Zeppelin',
    title: 'Kashmir',
  },
  {
    id: 6,
    station: talkStation,
    observed_at: '2026-10-22T21:36:00.000000Z',
    raw_title: 'The Evening News with Example Presenter',
    artist: null,
    title: null,
  },
  {
    id: 5,
    station: jazzStation,
    observed_at: '2026-10-22T21:33:00.000000Z',
    raw_title: 'Miles Davis - So What',
    artist: 'Miles Davis',
    title: 'So What',
  },
  {
    id: 4,
    station: rockStation,
    observed_at: '2026-10-22T21:29:00.000000Z',
    raw_title: 'Deep Purple - Child in Time',
    artist: 'Deep Purple',
    title: 'Child in Time',
  },
  {
    id: 3,
    station: jazzStation,
    observed_at: '2026-10-22T21:26:00.000000Z',
    raw_title: 'Nina Simone - Feeling Good',
    artist: 'Nina Simone',
    title: 'Feeling Good',
  },
  {
    id: 2,
    station: talkStation,
    observed_at: '2026-10-22T21:24:00.000000Z',
    raw_title: null,
    artist: null,
    title: null,
  },
  {
    id: 1,
    station: rockStation,
    observed_at: '2026-10-22T21:22:00.000000Z',
    raw_title: 'Black Sabbath - Paranoid',
    artist: 'Black Sabbath',
    title: 'Paranoid',
  },
] as const

export const metatable = {
  tracklisting: Schema.decodeUnknownSync(TracklistingSchema)(tracklisting),
} as const
