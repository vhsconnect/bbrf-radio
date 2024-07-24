import * as R from 'ramda'
const subtract = R.flip(R.subtract)

const radioModel = (v = []) => {
  const pub = {
    values: v,
    next(x) {
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
        let radio = this.values[this.values.length - 2]
        return radio
      }
    },
    remove() {
      return R.pipe(
        R.length,
        subtract(1),
        R.flip(R.take)(this.values),
        radioModel
      )(this.values)
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
