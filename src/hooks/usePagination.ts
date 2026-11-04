import React from 'react'
import { Effect } from 'effect'

interface Props<A> {
  // undefined while there is nothing to page through
  fetchPage:
    | ((offset: number) => Effect.Effect<ReadonlyArray<A>, unknown, never>)
    | undefined
  // a change starts over from the first page
  resetOn: React.DependencyList
  setItems: React.Dispatch<React.SetStateAction<ReadonlyArray<A>>>
  messageUser: (message: string) => void
  // plural noun for the end-of-results message, e.g. 'radios'
  label: string
}

const usePagination = <A>({
  fetchPage,
  resetOn,
  setItems,
  messageUser,
  label,
}: Props<A>) => {
  const [currentOffset, setCurrentOffset] = React.useState<number>(0)
  // pages answered for an earlier query are dropped
  const generation = React.useRef(0)

  React.useEffect(() => {
    const current = ++generation.current
    if (fetchPage) {
      messageUser('fetching...')
      setCurrentOffset(0)
      Effect.runPromise(fetchPage(0))
        .then(page => {
          if (current !== generation.current) return
          setItems(page)
          window.scrollTo({ top: 1, behavior: 'smooth' })
          messageUser('done')
        })
        .catch(() =>
          messageUser('Something went wrong! upstream might be down')
        )
    }
  }, resetOn)

  React.useEffect(() => {
    const current = generation.current
    if (fetchPage && currentOffset) {
      messageUser('fetching...')
      Effect.runPromise(fetchPage(currentOffset))
        .then(page => {
          if (current !== generation.current) return
          if (page.length === 0) {
            messageUser(`all ${label} have been fetched`)
          } else {
            setItems(items => items.concat(page))
            messageUser('done')
          }
        })
        .catch(() =>
          messageUser('Something went wrong! upstream might be down')
        )
    }
  }, [currentOffset])

  return { currentOffset, setCurrentOffset }
}

export default usePagination
