import React from 'react'
import { take, interval } from 'rxjs'
import * as R from 'ramda'

const Teleprompt = ({ text, ms }) => {
  const [displayed, setDisplayed] = React.useState('')
  React.useEffect(() => {
    interval(ms)
      .pipe(take(text.length))
      .subscribe(x => setDisplayed(R.slice(0, x, text + 1)))
  }, [text])

  return (
    <div>
      <p>{displayed}</p>
    </div>
  )
}

export default Teleprompt
