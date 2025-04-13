import React from 'react'
import * as R from 'ramda'
import RadioList from './RadioList'
import Button from './Button'
import Player from './Player'
import Teleprompt from './Teleprompt'
import DeleteFaultyStation from './DeleteFaultyStation'
import Flag from './Flag'
import useRegisterObservables from '../hooks/useRegisterObservables'
import useFilterRadios from '../hooks/useFilterRadios'
import radioModel from '../utils/radioModel'
import { request } from '../utils/httpHandlers'
import { radioApi } from '../../server/api/radioBrowser.mjs'
import { userAgent } from '../../server/userAgent.mjs'
import { getFavorites } from '../utils/urlWriter'
import { addFavorite, removeFavorite } from '../utils/urlWriter'

const DEFAULT_FADER_VALUE = 25
const DEFAULT_RESULT_LIMIT = 2000

export default function Main({ radioBrowserApiUrl, serverMode }) {
  const [channels, setChannels] = React.useState([])
  const [tag, setTag] = React.useState('')
  const [countrycode, setCountrycode] = React.useState('')
  const [name, setName] = React.useState('')
  const [favorites, setFavorites] = React.useState([])
  const [stationController, setStationController] = React.useState(radioModel())
  const [lockStations, setLockStations] = React.useState(false)
  const [currentOffset, setCurrentOffset] = React.useState(0)
  const [radioServer, setRadioServer] = React.useState('')
  const [radioFilter, setRadioFilter] = React.useState('')
  const [faderValue, setFaderValue] = React.useState(25)
  const [statusStack, setStatusStack] = React.useState([])
  const [deleteCandidate, setDeleteCandidate] = React.useState(null)

  const eMap = {
    server: {
      favorites: () => request('/favorites'),
      fader: () => request('/fader').then(R.prop('value')),
      searchField: (searchField, value, currentOffset) =>
        request(`/by${searchField}/${value}?offset=${currentOffset}`),
      addFavorite: radioPayload =>
        request(`/write/addStation/${radioPayload.stationuuid}`, {
          method: 'POST',
          body: JSON.stringify(radioPayload),
        }),
      removeFavorite: uuid =>
        request(`/write/removeStation/${uuid}`, { method: 'POST' }),
      radioServer: () => request('/radio-server').then(R.prop('server')),
      clicked: uuid => request(`/clicked/${uuid}`),
    },
    client: {
      favorites: () => {
        return Promise.resolve(getFavorites() ?? [])
      },
      fader: () => Promise.resolve(DEFAULT_FADER_VALUE),
      searchField: (searchField, value, currentOffset) =>
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
          : () => {
              throw new Error('unreacheable')
            },
      addFavorite,
      removeFavorite,
      radioServer: () => Promise.resolve(radioBrowserApiUrl),
      clicked: uuid => radioApi.clickStation(radioBrowserApiUrl, uuid),
    },
  }

  const api = eMap[serverMode ? 'server' : 'client']

  const queueStation = R.pipe(stationController.next, setStationController)

  const setStation = R.ifElse(
    Boolean,
    () => R.identity,
    () => queueStation
  )

  const defaultMessage = radioServer
    ? `Connected to ${radioServer}`
    : 'radio-browser service might be down'

  const getDefaultMessage = () => defaultMessage

  const messageUser = message =>
    setStatusStack([message].concat(getDefaultMessage()))

  const tagsInput = React.useRef(null)
  const ccInput = React.useRef(null)
  const nameInput = React.useRef(null)

  useRegisterObservables({
    setTag,
    setCountrycode,
    setName,
    setFavorites,
    setRadioFilter,
    setChannels,
    messageUser,
    radioFilter,
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
      api
        .searchField(searchField, value, 0)
        .then(setChannels)
        .then(() => {
          window.scrollTo({ top: true, behavior: 'smooth' })
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
      api
        .searchField(searchField, value, currentOffset)
        .then(
          R.ifElse(
            R.isEmpty,
            () => messageUser('all radios have been fetched'),
            R.pipe(R.concat(channels), setChannels, () => messageUser('done'))
          )
        )
        .catch(() =>
          messageUser('Something went wrong! upstream might be down')
        )
    }
  }, [currentOffset])

  React.useEffect(() => {
    api
      .radioServer()
      .then(setRadioServer)
      .catch(() => messageUser('radio-browser service appears to be down'))
  }, [radioBrowserApiUrl])

  React.useEffect(() => {
    api.fader().then(setFaderValue)
  }, [])

  React.useEffect(() => {
    setStatusStack([defaultMessage])
  }, [radioServer])

  const removeFromFavorites = uuid => {
    api
      .removeFavorite(uuid)
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
              onClick={() => {
                api
                  .favorites()
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
              R.pipe(
                R.map(R.prop('stationuuid')),
                R.includes(deleteCandidate.stationuuid)
              )(favorites) && (
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
