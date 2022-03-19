import React from 'react'
import * as R from 'ramda'
import RadioList from './RadioList'
import Button from './Button'
import Player from './Player'
import useRegisterObservables from '../hooks/useRegisterObservables'
import radioController from '../utils/radioController'

export default function Main() {
  const [channels, setChannels] = React.useState([])
  const [tag, setTag] = React.useState('')
  const [countrycode, setCountrycode] = React.useState('')
  const [name, setName] = React.useState('')
  const [favorites, setFavorites] = React.useState([])
  const [currentStation, setCurrentStation] = React.useState(radioController())

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

  return (
    <div id="player">
      <div>
        <input className="little-" type="text" id="tags" placeholder="by tag" />
        <input
          className="little-margin"
          type="text"
          id="countrycode"
          placeholder="by country"
        />
        <input
          className="little-margin"
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
      <Player
        currentStation={currentStation}
        favorites={favorites}
        backtrackCurrentStation={R.pipe(
          currentStation.remove,
          setCurrentStation
        )}
      />
      <RadioList
        favorites={favorites}
        channels={channels}
        setCurrentStation={R.pipe(currentStation.next, setCurrentStation)}
      />
    </div>
  )
}
