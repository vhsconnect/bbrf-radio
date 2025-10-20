import React, { useEffect } from 'react'
import * as R from 'ramda'

interface Props {
  setCurrentOffset: (offset: number) => void
  currentOffset: number
  paginationTarget: boolean
  info: any
  observerId: string
  [key: string]: any
}

const withSplashed = (Child: React.FC<any>) => (props: Props) => {
  const { setCurrentOffset, currentOffset, paginationTarget, info } = props

  useEffect(() => {
    const _setCurrentOffset = R.memoizeWith(String, setCurrentOffset)
    const splashObserver = new IntersectionObserver(
      R.when(R.pathEq(true, [0, 'isIntersecting']), () =>
        _setCurrentOffset(currentOffset + 1)
      ),

      {
        root: null,
        rootMargin: '0px',
        threshold: 1.0,
      }
    )
    const target = document.getElementById(props.observerId)

    if (target) {
      if (paginationTarget) {
        splashObserver.observe(target)

        return () => {
          splashObserver.unobserve(target)
        }
      }
    }
  }, [info])

  return (
    <span id={props.observerId}>
      <Child {...props} />
    </span>
  )
}

export default withSplashed
