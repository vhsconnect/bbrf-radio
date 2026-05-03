import type { Radio, RadioInterface, RadioStream } from '../types'
import { createLogger } from './debug'

const log = createLogger('radio')

const radioL = (
  history: ReadonlyArray<RadioStream> = []
): RadioInterface => ({
  current: history[history.length - 1],
  previous: history.length > 1 ? history[history.length - 2] : undefined,
  hasHistory: history.length > 1,

  push(x: Radio) {
    const cacheBust = Math.random() * 100
    const url = (x.url_resolved || decodeURIComponent(x.url)) + '?' + cacheBust.toFixed(2)
    const stream = new Audio(url)
    stream.preload = 'none'
    stream.load()
    stream.volume = history.length > 0 ? 0 : 1
    log.info('push', { name: x.name, url, bitrate: x.bitrate, historyLen: history.length, initialVolume: stream.volume })
    return radioL([...history, { ...x, stream }])
  },

  pop() {
    const removed = history[history.length - 1]
    log.info('pop', { name: removed?.name, remainingHistory: history.length - 1 })
    return radioL(history.slice(0, -1))
  },
})

export default radioL
