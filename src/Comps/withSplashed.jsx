import React, { useEffect } from 'react'
import * as R from 'ramda'
const withSplashed = Child => props => {
  const { setCurrentOffset, currentOffset, paginationTarget, info } = props

  useEffect(() => {
    const _setCurrentOffset = R.memoizeWith(R.identity, setCurrentOffset)
    let splashObserver = new IntersectionObserver(
      R.when(R.pathEq([0, 'isIntersecting'], true), () =>
        _setCurrentOffset(currentOffset + 1)
      ),
      {
        root: null,
        rootMargin: '0px',
        threshold: 1.0,
      }
    )
    const target = document.getElementById(props.observerId)
    paginationTarget ? splashObserver.observe(target) : null
    return paginationTarget
      ? () => {
          console.log('executing cleanup')
          splashObserver.unobserve(target)
        }
      : null
  }, [info])

  return (
    <span id={props.observerId}>
      <Child {...props} />
    </span>
  )
}

export default withSplashed
