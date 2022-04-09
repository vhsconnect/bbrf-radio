import React from 'react'
import * as R from 'ramda'
import RadioList from './RadioList'
import Button from './Button'
import Player from './Player'
import Teleprompt from './Teleprompt'
import useRegisterObservables from '../hooks/useRegisterObservables'
import radioModel from '../utils/radioModel'
import Flag from './Flag'

export default function Main() {
  const [channels, setChannels] = React.useState([])
  const [tag, setTag] = React.useState('')
  const [countrycode, setCountrycode] = React.useState('')
  const [name, setName] = React.useState('')
  const [favorites, setFavorites] = React.useState([])
  const [stationController, setStationController] = React.useState(radioModel())
  const [radioServer, setRadioServer] = React.useState('')
  
  // observables on input fields
  useRegisterObservables({ setTag, setCountrycode, setName, setFavorites })

  React.useEffect(() => {
    const searchField = tag
      ? 'tag'
      : countrycode
      ? 'countrycode'
      : name
      ? 'name'
      : undefined
    const value = tag || countrycode || name
    if (searchField) {
      fetch(`/by${searchField}/` + value, {
        method: 'GET',
      })
        .then(data => data.json())
        .then(setChannels)
        .catch(e => console.error(e))
    }
  }, [tag, countrycode, name])

  React.useEffect(() => {
    fetch('/radio-server')
      .then(data => data.json())
      .then(R.prop('server'))
      .then(setRadioServer)
  }, [])

  return (
    <div>
      <div>
        <input className="input-fields" type="text" id="tags" placeholder="by tag" />
        <input
          className="input-fields"
          type="text"
          id="countrycode"
          placeholder="by country"
        />
        <input
          className="input-fields"
          type="text"
          id="name"
          placeholder="by name"
        />
        <Button
          text="favs"
          onClick={() => {
            fetch('/favorites')
              .then(data => data.json())
              .then(setChannels)
          }}
        />
      </div>
      {radioServer && (
        <Teleprompt ms={30} text={`Connected to ${radioServer}`} />
      )}
      <Player
        stationController={stationController}
        favorites={favorites}
        backtrackCurrentStation={R.pipe(
          stationController.remove,
          setStationController
        )}
      />
      <div className="under-player">
        <RadioList
          favorites={favorites}
          channels={channels}
          setStationController={R.pipe(
            stationController.next,
            setStationController
          )}
        />

        {stationController.current && (
          <Flag countrycode={stationController.current?.countrycode} />
        )}
      </div>
    </div>
  )
}
