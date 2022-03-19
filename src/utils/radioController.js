import * as R from 'ramda'
const radioController = (v = []) => {
  const pub = {
    values: v,
    next(x) {
      return radioController(
        this.values.concat({
          ...x,
          stream: new Audio(x.url_resolved),
        })
      )
    },
    get last() {
      return this.values.length > 1 && this.values[this.values.length - 2]
    },
    remove() {
      return radioController(R.take(R.length(this.values) - 1, this.values))
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

export default radioController
