import React from 'react'

import type { Subscription } from 'rxjs'
import { concatMap, interval, map, take, timer } from 'rxjs'
import * as R from 'ramda'

const Teleprompt = ({ textStack, ms }: { textStack: string[]; ms: number }) => {
  const [displayed, setDisplayed] = React.useState('')
  const subscriptionsRef = React.useRef<Subscription[]>([])
  const lastFirstElement = React.useRef<string | undefined>(undefined)

  React.useEffect(() => {
    // Same content — do not interrupt the running animation
    if (textStack[0] === lastFirstElement.current) {
      return
    }
    lastFirstElement.current = textStack[0]

    // Tear down any in-flight animation before starting a new one
    subscriptionsRef.current.forEach(x => x.unsubscribe())
    subscriptionsRef.current = []

    if (!textStack.length) {
      setDisplayed('')
      return
    }

    const newSubs: Subscription[] = []
    textStack
      .map(text =>
        interval(ms).pipe(
          take(text.length),
          map(position => ({ position, text }))
        )
      )
      .map(($text, index) => timer(index * 5000).pipe(concatMap(() => $text)))
      .forEach($text =>
        newSubs.push(
          $text.subscribe(({ position, text }) =>
            setDisplayed(
              R.concat(
                R.slice(0, position + 1, text),
                R.pipe(R.repeat(' '), R.join(''))(text.length - (position + 1))
              )
            )
          )
        )
      )
    subscriptionsRef.current = newSubs
  }, [textStack, ms])

  // Final cleanup on unmount only
  React.useEffect(() => {
    return () => {
      subscriptionsRef.current.forEach(x => x.unsubscribe())
    }
  }, [])

  return (
    <div>
      <p>{displayed}</p>
    </div>
  )
}

export default Teleprompt
