import React from 'react'
import ReactDOM from 'react-dom'
import Main from './Main'

const App = () => (
  <div>
    <Main />
  </div>
)

ReactDOM.render(React.createElement(App), document.getElementById('app'))
