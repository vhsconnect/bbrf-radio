import type { Radio, RadioInterface, RadioStream } from '../types'

const radioL = (
  history: ReadonlyArray<RadioStream> = []
): RadioInterface => ({
  current: history[history.length - 1],
  previous: history.length > 1 ? history[history.length - 2] : undefined,
  hasHistory: history.length > 1,

  push(x: Radio) {
    const cacheBust = Math.random() * 100
    const stream = new Audio(
      (x.url_resolved || decodeURIComponent(x.url)) + '?' + cacheBust.toFixed(2)
    )
    stream.preload = 'none'
    stream.load()
    stream.volume = history.length > 0 ? 0 : 1
    return radioL([...history, { ...x, stream }])
  },

  pop() {
    return radioL(history.slice(0, -1))
  },
})

export default radioL
