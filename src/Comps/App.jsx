import React from 'react'
import ReactDOM from 'react-dom'
import Main from './Main'

const App = () => {
  return (
    <div>
      <Main radioBrowserApiUrl={null} serverMode={true} />
    </div>
  )
}

ReactDOM.render(React.createElement(App), document.getElementById('app'))
