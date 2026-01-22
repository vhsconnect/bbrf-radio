import * as R from 'ramda'
import type { Radio, RadioInterface, RadioStream } from '../types'

const radioModel = (xs: Array<RadioStream> = []): RadioInterface => {
  const pub: RadioInterface = {
    values: xs,
    next(x: Radio) {
      // dont cache audio packets
      const cacheBust = Math.random() * 100
      const stream = new Audio(
        (x.url_resolved || decodeURIComponent(x.url)) +
          '?' +
          cacheBust.toFixed(2)
      )

      stream.preload = 'none'
      stream.load()
      stream.volume = this.up() ? 0 : 1
      return radioModel(
        this.values.concat({
          ...x,
          stream,
        })
      )
    },
    get last() {
      if (this.values.length > 1) {
        const radio = this.values[this.values.length - 2]
        return radio
      }
    },
    remove() {
      return radioModel(R.dropLast(1, this.values))
    },
    get current() {
      return this.values[this.values.length - 1]
    },
    up() {
      return this.values.length > 0
    },
  }

  pub.next = pub.next.bind(pub)
  pub.remove = pub.remove.bind(pub)
  pub.up = pub.up.bind(pub)
  return pub
}

export default radioModel
