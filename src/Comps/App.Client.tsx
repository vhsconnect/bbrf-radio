import React, { useEffect, useState } from 'react'
import ReactDOM from 'react-dom'
import Main from './Main'
import { discoverRadioBrowserApiUrl } from '../utils/radioBrowserDiscovery'

const App = () => {
  const [radioBrowserApiUrl, setRadioBrowserApiUrl] = useState<string | null>(
    null
  )

  useEffect(() => {
    discoverRadioBrowserApiUrl().then(setRadioBrowserApiUrl)
  }, [])

  return (
    <div>
      <Main radioBrowserApiUrl={radioBrowserApiUrl} serverMode={false} />
    </div>
  )
}

ReactDOM.render(React.createElement(App), document.getElementById('app'))
