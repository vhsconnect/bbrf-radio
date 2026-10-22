import { Schema } from 'effect'

const RadioSchema = Schema.Struct({
  stationuuid: Schema.String,
  url: Schema.String,
  url_resolved: Schema.optional(Schema.String),
  name: Schema.String,
  countrycode: Schema.String,
  bitrate: Schema.Number,
})

export const RadioApiUpstreamSchema = Schema.Struct({
  server: Schema.String,
})

export const RadioStreamSchema = Schema.extend(
  RadioSchema,
  Schema.Struct({ stream: Schema.instanceOf(HTMLAudioElement) })
)

export const RadioCollectionSchema = Schema.Array(RadioSchema)

const TagsSchema = Schema.transform(
  Schema.String,
  Schema.Array(Schema.String),
  {
    strict: true,
    decode: tags =>
      tags
        .split(',')
        .map(tag => tag.trim())
        .filter(tag => tag.length > 0),
    encode: tags => tags.join(','),
  }
)

const TrackStationSchema = Schema.extend(
  RadioSchema,
  Schema.Struct({ tags: TagsSchema })
)

const TrackSchema = Schema.Struct({
  id: Schema.Number,
  station: TrackStationSchema,
  observed_at: Schema.DateFromString,
  raw_title: Schema.NullOr(Schema.String),
  artist: Schema.NullOr(Schema.String),
  title: Schema.NullOr(Schema.String),
})

export const TracklistingSchema = Schema.Array(TrackSchema)

export type RadioCollection = Schema.Schema.Type<typeof RadioCollectionSchema>

export type Radio = Schema.Schema.Type<typeof RadioSchema>

export type RadioStream = Schema.Schema.Type<typeof RadioStreamSchema>

export type TrackStation = Schema.Schema.Type<typeof TrackStationSchema>

export type Track = Schema.Schema.Type<typeof TrackSchema>

export type Tracklisting = Schema.Schema.Type<typeof TracklistingSchema>

export type RadioApiUpstream = Schema.Schema.Type<typeof RadioApiUpstreamSchema>

export type RadioInterface = {
  current: RadioStream
  previous: RadioStream | undefined
  hasHistory: boolean
  push: (x: Radio) => RadioInterface
  pop: () => RadioInterface
}
