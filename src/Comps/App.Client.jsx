import React, { useState, useEffect } from 'react'
import ReactDOM from 'react-dom'
import Main from './Main'
import * as R from 'ramda'

const cloudflareDns = 'https://cloudflare-dns.com/dns-query'
const radioBrowserRequest = () =>
  fetch(cloudflareDns + '?name=_api._tcp.radio-browser.info' + '&type=SRV', {
    headers: {
      Accept: 'application/dns-json',
    },
  })

const App = () => {
  const [radioBrowserApiUrl, setRadioBrowserApiUrl] = useState(null)

  useEffect(() => {
    radioBrowserRequest()
      .then(x => x.json())
      .then(
        R.pipe(
          R.prop('Answer'),
          R.head,
          R.prop('data'),
          R.split(' '),
          x => x[3],
          setRadioBrowserApiUrl
        )
      )
  }, [])

  return (
    <div>
      <Main radioBrowserApiUrl={radioBrowserApiUrl} serverMode={false} />
    </div>
  )
}

ReactDOM.render(React.createElement(App), document.getElementById('app'))
