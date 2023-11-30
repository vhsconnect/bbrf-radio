import React from 'react'
import * as R from 'ramda'
import RadioList from './RadioList'
import Button from './Button'
import Player from './Player'
import Teleprompt from './Teleprompt'
import useRegisterObservables from '../hooks/useRegisterObservables'
import useFilterRadios from '../hooks/useFilterRadios'
import radioModel from '../utils/radioModel'
import Flag from './Flag'
import { request } from '../utils/httpHandlers'

export default function Main() {
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

  const defaultMessage = radioServer
    ? `Connected to ${radioServer}`
    : 'radio-browser service might be down'
  const messageUser = message =>
    setStatusStack([message].concat(defaultMessage))

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
      request(`/by${searchField}/${value}?offset=0`, {
        method: 'GET',
      })
        .then(data => data.json())
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
      request(`/by${searchField}/${value}?offset=${currentOffset}`, {
        method: 'GET',
      })
        .then(data => data.json())
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
    request('/radio-server')
      .then(data => data.json())
      .then(R.prop('server'))
      .then(setRadioServer)
      .catch(() => messageUser('radio-browser service appears to be down'))
  }, [])

  React.useEffect(() => {
    request('/fader')
      .then(data => data.text())
      .then(setFaderValue)
  }, [])

  React.useEffect(() => {
    setStatusStack([defaultMessage])
  }, [radioServer])

  return (
    <div>
      <div className="sticky">
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
              request('/favorites')
                .then(data => data.json())
                .then(
                  R.tap(() => {
                    setCountrycode('')
                    setTag('')
                    setName('')
                  })
                )
                .then(setChannels)
                .catch(() => messageUser("Couldn't fetch favorties"))
            }}
          />
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
          <Teleprompt ms={30} textStack={statusStack} />
          {radioFilter ? (
            <div style={{ display: 'flex', alignItems: 'center' }}>
              filter: {radioFilter} - Escape to clear
            </div>
          ) : (
            <div style={{ display: 'flex', alignItems: 'center' }}>
              type to filter - Escape to clear
            </div>
          )}
        </div>
        <Player
          stationController={stationController}
          favorites={favorites}
          setLockStations={setLockStations}
          backtrackCurrentStation={R.pipe(
            stationController.remove,
            setStationController
          )}
          messageUser={messageUser}
          setFavorites={setFavorites}
          msToVolumeRatio={faderValue}
          setStationController={R.pipe(
            stationController.next,
            setStationController
          )}
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
          setStationController={R.pipe(
            stationController.next,
            setStationController
          )}
          setLockStations={setLockStations}
          setCurrentOffset={setCurrentOffset}
          currentOffset={currentOffset}
          radioFilter={radioFilter}
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
