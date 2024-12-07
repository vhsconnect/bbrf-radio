import React from 'react'
import { concatMap, timer, take, interval, map } from 'rxjs'
import * as R from 'ramda'

const Teleprompt = ({ textStack, ms }) => {
  const [displayed, setDisplayed] = React.useState('')
  const lastTextStack = React.useRef(null)

  let subscriptions = []
  React.useEffect(() => {
    // values are the same - do not animate
    if (textStack[0] !== lastTextStack.current?.at(0)) {
      textStack
        .map(text =>
          interval(ms).pipe(
            take(text.length),
            map(position => ({ position, text }))
          )
        )
        .map(($text, index) => timer(index * 5000).pipe(concatMap(() => $text)))
        .forEach($text =>
          subscriptions.push(
            $text.subscribe(({ position, text }) =>
              setDisplayed(
                R.concat(
                  R.slice(0, position + 1, text),
                  R.pipe(
                    R.repeat(' '),
                    R.join('')
                  )(text.length - (position + 1))
                )
              )
            )
          )
        )
      return () => {
        subscriptions.forEach(x => x.unsubscribe())
        lastTextStack.current = textStack
      }
    }
  }, [textStack])

  return (
    <div>
      <p>{displayed}</p>
    </div>
  )
}

export default Teleprompt
