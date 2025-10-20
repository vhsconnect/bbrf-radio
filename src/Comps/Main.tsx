import React from 'react'
import * as R from 'ramda'
import { Effect, Option, Schema, pipe } from 'effect'
import type { UnknownException } from 'effect/Cause'
import useRegisterObservables from '../hooks/useRegisterObservables'
import useFilterRadios from '../hooks/useFilterRadios'
import radioModel from '../utils/radioModel'
import { request } from '../utils/httpHandlers'
import { radioApi } from '../../server/api/radioBrowser.mjs'
import { userAgent } from '../../server/userAgent.mjs'
import { addFavorite, getFavorites, removeFavorite } from '../utils/urlWriter'
import type { Radio, RadioCollection } from '../types'
import { RadioApiUpstreamSchema, RadioCollectionSchema } from '../types'
import Flag from './Flag'
import DeleteFaultyStation from './DeleteFaultyStation'
import Teleprompt from './Teleprompt'
import Player from './Player'
import Button from './Button'
import RadioList from './RadioList'

const DEFAULT_FADER_VALUE = 25
const DEFAULT_RESULT_LIMIT = 2000

interface Props {
  serverMode: boolean
  radioBrowserApiUrl: string | null
}

export type Api = {
  favorites: () => Effect.Effect<RadioCollection, UnknownException, never>
  addFavorite: (
    radio: Radio
  ) => Effect.Effect<RadioCollection, UnknownException, never>
  removeFavorite: (
    uuid: string
  ) => Effect.Effect<RadioCollection, UnknownException, never>
  searchField: (
    searchField: string,
    value: string,
    currentOffset: number
  ) => Effect.Effect<RadioCollection, UnknownException, never>
  fader: () => Effect.Effect<number, number, never>
  radioServer: () => Effect.Effect<
    Option.Option<string>,
    Option.Option<never>,
    never
  >
  clicked: (uuid: string) => Effect.Effect<unknown, never, never>
}

export default function Main({ radioBrowserApiUrl, serverMode }: Props) {
  const [channels, setChannels] = React.useState<RadioCollection>([])
  const [tag, setTag] = React.useState<string>('')
  const [countrycode, setCountrycode] = React.useState<string>('')
  const [name, setName] = React.useState<string>('')
  const [favorites, setFavorites] = React.useState<RadioCollection>([])
  const [stationController, setStationController] = React.useState(radioModel())
  const [lockStations, setLockStations] = React.useState<boolean>(false)
  const [currentOffset, setCurrentOffset] = React.useState<number>(0)
  const [radioServer, setRadioServer] = React.useState<
    string | undefined | null
  >('')
  const [radioFilter, setRadioFilter] = React.useState<string>('')
  const [faderValue, setFaderValue] =
    React.useState<number>(DEFAULT_FADER_VALUE)
  const [statusStack, setStatusStack] = React.useState<string[]>([])
  const [deleteCandidate, setDeleteCandidate] = React.useState<Radio | null>(
    null
  )

  const apiMap = {
    server: {
      favorites: () =>
        Effect.tryPromise(() =>
          request('/favorites', {}).then(
            Schema.decodeUnknownPromise(RadioCollectionSchema)
          )
        ),
      fader: () =>
        pipe(
          Effect.tryPromise(() =>
            request('/fader').then(
              Schema.decodeUnknownPromise(
                Schema.Struct({ value: Schema.Number })
              )
            )
          ),
          Effect.mapBoth({
            onFailure: () => DEFAULT_FADER_VALUE,
            onSuccess: x => x.value,
          })
        ),
      searchField: (
        searchField: string,
        value: string,
        currentOffset: number
      ) =>
        Effect.tryPromise(() =>
          request(`/by${searchField}/${value}?offset=${currentOffset}`).then(
            Schema.decodeUnknownPromise(RadioCollectionSchema)
          )
        ),
      addFavorite: (radioPayload: Radio) =>
        Effect.tryPromise(() =>
          request(`/write/addStation/${radioPayload.stationuuid}`, {
            method: 'POST',
            body: JSON.stringify(radioPayload),
          }).then(Schema.decodeUnknownPromise(RadioCollectionSchema))
        ),
      removeFavorite: (uuid: string) =>
        Effect.tryPromise(() =>
          request(`/write/removeStation/${uuid}`, {
            method: 'POST',
          }).then(Schema.decodeUnknownPromise(RadioCollectionSchema))
        ),
      radioServer: () =>
        pipe(
          Effect.tryPromise(() =>
            request('/radio-server').then(
              Schema.decodeUnknownPromise(RadioApiUpstreamSchema)
            )
          ),
          Effect.mapBoth({
            onSuccess: decoded => Option.some(decoded.server),
            onFailure: () => Option.none(),
          })
        ),
      clicked: (uuid: string) =>
        Effect.promise(() => request(`/clicked/${uuid}`)),
    },
    client: {
      favorites: () =>
        Effect.promise(() => Promise.resolve(getFavorites() ?? [])),
      fader: () =>
        pipe(
          Effect.promise(() => Promise.resolve(DEFAULT_FADER_VALUE)),
          Effect.mapError(() => DEFAULT_FADER_VALUE)
        ),
      searchField: (
        searchField: string,
        value: string,
        currentOffset: number
      ) => {
        const f =
          searchField === 'tag'
            ? radioApi.getByTag(
                radioBrowserApiUrl,
                value,
                currentOffset,
                DEFAULT_RESULT_LIMIT
              )
            : searchField === 'countrycode'
            ? radioApi.getByCountryCode(
                radioBrowserApiUrl,
                value,
                currentOffset,
                DEFAULT_RESULT_LIMIT
              )
            : searchField === 'name'
            ? radioApi.getByName(
                radioBrowserApiUrl,
                value,
                currentOffset,
                DEFAULT_RESULT_LIMIT
              )
            : Promise.reject('unreacheable error')

        return Effect.tryPromise(() =>
          f.then(Schema.decodeUnknownPromise(RadioCollectionSchema))
        )
      },

      addFavorite: (radio: Radio) =>
        Effect.tryPromise<Readonly<RadioCollection>>(() => addFavorite(radio)),
      removeFavorite: (uuid: string) =>
        Effect.tryPromise<Readonly<RadioCollection>>(() =>
          removeFavorite(uuid)
        ),
      radioServer: () =>
        pipe(
          Effect.promise(() =>
            radioBrowserApiUrl
              ? Promise.resolve(radioBrowserApiUrl)
              : Promise.reject(Error('radio-browser-api url not available'))
          ),
          Effect.mapBoth({
            onSuccess: Option.some,
            onFailure: Option.none,
          })
        ),
      clicked: (uuid: string) =>
        Effect.promise(() => radioApi.clickStation(radioBrowserApiUrl, uuid)),
    },
  }

  const api: Api = apiMap[serverMode ? 'server' : 'client']

  const queueStation = R.pipe(stationController.next, setStationController)

  const setStation = (x: boolean) => (x ? R.identity : queueStation)

  const defaultMessage = radioServer
    ? `Connected to ${radioServer}`
    : 'radio-browser service might be down'

  const getDefaultMessage = () => defaultMessage

  const messageUser = (message: string) =>
    setStatusStack([message].concat(getDefaultMessage()))

  const tagsInput = React.useRef(null)
  const ccInput = React.useRef(null)
  const nameInput = React.useRef(null)

  useRegisterObservables({
    setTag,
    setCountrycode,
    setName,
    setFavorites,
    setChannels,
    messageUser,
    api,
  })

  useFilterRadios({
    setRadioFilter,
    radioFilter,
    tagsInput,
    ccInput,
    nameInput,
  })

  React.useEffect(() => {
    messageUser('fetching...')
    const searchField = tag
      ? 'tag'
      : countrycode
      ? 'countrycode'
      : name
      ? 'name'
      : undefined
    const value = tag || countrycode || name
    if (searchField) {
      setCurrentOffset(0)
      Effect.runPromise(api.searchField(searchField, value, 0))
        .then(setChannels)
        .then(() => {
          window.scrollTo({ top: 1, behavior: 'smooth' })
        })
        .then(() => messageUser('done'))
        .catch(() =>
          messageUser('Something went wrong! upstream might be down')
        )
    }
  }, [tag, countrycode, name])

  React.useEffect(() => {
    const searchField = tag
      ? 'tag'
      : countrycode
      ? 'countrycode'
      : name
      ? 'name'
      : undefined
    const value = tag || countrycode || name
    // don't trigger on offset reset
    if (searchField && currentOffset) {
      messageUser('fetching...')
      Effect.runPromise(api.searchField(searchField, value, currentOffset))
        .then(
          R.ifElse(
            R.isEmpty,
            () => messageUser('all radios have been fetched'),
            R.pipe(R.concat<Radio>(channels), setChannels, () =>
              messageUser('done')
            )
          )
        )
        .catch(() =>
          messageUser('Something went wrong! upstream might be down')
        )
    }
  }, [currentOffset])

  React.useEffect(() => {
    Effect.runPromise(
      pipe(
        api.radioServer(),
        Effect.tap(
          Option.match({
            onNone: () =>
              Effect.sync(() =>
                messageUser('radio-browser service appears to be down')
              ),
            onSome: server => Effect.sync(() => setRadioServer(server)),
          })
        )
      )
    )
  }, [radioBrowserApiUrl])

  React.useEffect(() => {
    Effect.runPromise(api.fader()).then(x => setFaderValue(x))
  }, [])

  React.useEffect(() => {
    setStatusStack([defaultMessage])
  }, [radioServer])

  const removeFromFavorites = (uuid: string) => {
    Effect.runPromise(api.removeFavorite(uuid))
      .then(setFavorites)
      .catch(() => messageUser("Couldn't remove favorite"))
  }

  return (
    <div>
      <div className="sticky">
        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
          <div>
            <input
              ref={tagsInput}
              className="input-fields"
              type="text"
              id="tags"
              placeholder="by tag"
            />
            <input
              ref={ccInput}
              className="input-fields"
              type="text"
              id="countrycode"
              placeholder="by countrycode"
            />
            <input
              ref={nameInput}
              className="input-fields"
              type="text"
              id="name"
              placeholder="by name"
            />
            <Button
              text="favs"
              disabled={false}
              onClick={() => {
                Effect.runPromise(api.favorites())
                  .then(
                    R.tap(() => {
                      setCountrycode('')
                      setTag('')
                      setName('')
                    })
                  )
                  .then(setChannels)
                  .then(R.tap(() => setRadioFilter('')))
                  .catch(() => messageUser("Couldn't fetch favorties"))
              }}
            />
          </div>
          <p className="mobile-hidden" style={{ paddingRight: '10px' }}>
            {userAgent.split(' ')[1]}
          </p>
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
          <span>
            <Teleprompt ms={30} textStack={statusStack} />
            {deleteCandidate &&
              favorites
                .map(x => x.stationuuid)
                .includes(deleteCandidate.stationuuid) && (
                <DeleteFaultyStation
                  deleteCandidate={deleteCandidate}
                  setDeleteCandidate={setDeleteCandidate}
                  removeFromFavorites={removeFromFavorites}
                />
              )}
          </span>

          <div className="mobile-hidden">
            <div style={{ display: 'flex', alignItems: 'center' }}>
              {radioFilter ? `filter: ${radioFilter} ` : 'type to filter '}-
              Escape to clear
            </div>
          </div>
        </div>
        <Player
          stationController={stationController}
          removeFromFavorites={removeFromFavorites}
          favorites={favorites}
          backtrackCurrentStation={R.pipe(
            R.pipe(R.prop('values'), R.last, setDeleteCandidate),
            stationController.remove,
            setStationController
          )}
          defaultMessage={defaultMessage}
          messageUser={messageUser}
          setFavorites={setFavorites}
          setLockStations={setLockStations}
          setStationController={setStation(lockStations)}
          setStatusStack={setStatusStack}
          msToVolumeRatio={faderValue}
          api={api}
        />
      </div>
      <div className="under-player">
        <RadioList
          channels={channels}
          isFavsList={R.pipe(
            R.reject(R.isEmpty),
            R.isEmpty
          )([name, countrycode, tag])}
          lockStations={lockStations}
          setStationController={setStation(lockStations)}
          setLockStations={setLockStations}
          setCurrentOffset={setCurrentOffset}
          currentOffset={currentOffset}
          radioFilter={radioFilter}
          api={api}
        />
        <div className="right-panel">
          {stationController.current && (
            <Flag countrycode={stationController.current?.countrycode} />
          )}
        </div>
      </div>
    </div>
  )
}
