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

export type RadioCollection = Schema.Schema.Type<typeof RadioCollectionSchema>

export type Radio = Schema.Schema.Type<typeof RadioSchema>

export type RadioStream = Schema.Schema.Type<typeof RadioStreamSchema>

export type RadioApiUpstream = Schema.Schema.Type<typeof RadioApiUpstreamSchema>

export type RadioInterface = {
  values: Array<RadioStream>
  last: RadioStream | undefined
  current: RadioStream
  next: (x: Radio) => RadioInterface
  remove: () => RadioInterface
  up: () => boolean
}
