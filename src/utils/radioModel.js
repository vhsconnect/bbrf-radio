import * as R from 'ramda'
const subtract = R.flip(R.subtract)

//solves the cached audio data problem in chromium
//not firefox
//side-effect 🚓
let slug = 0

const radioModel = (v = []) => {
  const pub = {
    values: v,
    next(x) {
      const stream = new Audio(x.url_resolved + '?' + slug++)
      stream.preload = 'none'
      stream.volume = this.up() ? 0 : 1
      return radioModel(
        this.values.concat({
          ...x,
          stream,
        })
      )
    },
    get last() {
      return this.values.length > 1 && this.values[this.values.length - 2]
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
