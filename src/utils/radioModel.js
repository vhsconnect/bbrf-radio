import * as R from 'ramda'
const radioModel = (v = []) => {
  const pub = {
    values: v,
    next(x) {
      return radioModel(
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
      return radioModel(R.take(R.length(this.values) - 1, this.values))
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
