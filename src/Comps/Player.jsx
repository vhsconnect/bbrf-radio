import React from 'react'
import Button from './Button'
import { interval } from 'rxjs'
import { takeWhile, map } from 'rxjs/operators'
import * as R from 'ramda'

const fader = interval(20).pipe(
  map(R.pipe(R.subtract(100), R.flip(R.divide)(100))),
  takeWhile(R.flip(R.gte)(0))
)

const Player = ({ currentStation, backtrackCurrentStation }) => {
  const current = currentStation.current?.stream
  const last = currentStation.last?.stream

  React.useEffect(() => {
    if (currentStation.up()) {
      current.onplaying = () => {
        last && 
          fader.subscribe({
            next(x) {
              last.volume = x
              x === 0 ? last.pause() : null
            },
            complete() {
              last.pause()
            },
          })
      }
      current.play().catch(backtrackCurrentStation)
    }
  }, [currentStation])

  return current ? (
    <div className="radio-player">
      <Button
        text="⏯"
        onClick={() => {
          current.paused ? current.play() : current.pause()
        }}
      />
      {currentStation.current.name}
      <input
        type="range"
        min={0}
        max={10}
        defaultValue={current?.volume * 10 || 10}
        onChange={e => {
          current.volume = e.target.value / 10
        }}
      />
    </div>
  ) : (
    <div></div>
  )
}
export default Player
