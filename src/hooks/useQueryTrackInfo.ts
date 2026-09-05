import { useEffect } from 'react'
import * as R from 'ramda'
import type { RadioInterface  } from '../types'

interface Props {
  stationController: RadioInterface
  current: HTMLAudioElement
  defaultMessage: string
  setStatusStack: (xs: string[]) => void
}

export default ({
  stationController,
  current,
  defaultMessage,
  setStatusStack,
}: Props) => {
  useEffect(() => {
    let timeoutTime = 10 * 1000
    // set on cleanup: an in-flight poll from a previous station must not
    // overwrite the status of the station that is playing now
    let cancelled = false

    const f = () => {
      if (stationController.current) {
        const url = stationController.current.url

        const maybeXsl = R.pipe<[string], string[], string[], string, string>(
          R.split('/'),
          R.dropLast(1),
          R.join('/'),
          R.concat(R.__, '/status-json.xsl')
        )

        const maybeXsl2 = R.pipe<[string], string[], string[], string, string>(
          R.split('/'),
          R.dropLast(2),
          R.join('/'),
          R.concat(R.__, '/status-json.xsl')
        )

        const normalize: (x: string | undefined) => string | undefined = R.when(
          R.complement(R.isNil),
          R.pipe(
            /*
             * radioL.push appends a ?cachebust query to the stream url while
             * the listenurl reported by status-json.xsl never has one. Without
             * stripping queries the source match below fails for every station
             * whose xsl reports an array of sources (multi-mount icecast), so
             * their track info would never display.
             */
            R.replace(/\?.*/, ''),
            R.replace(':80', ''),
            R.replace('https', 'http')
          )
        )

        Promise.allSettled([fetch(maybeXsl(url)), fetch(maybeXsl2(url))])
          .then(results =>
            results.filter(x => x.status === 'fulfilled').map(x => x.value)
          )
          .then(R.head)
          .then(x => (x as Response).json())
          .then(x => x.icestats?.source)
          .then(
            R.when(
              Array.isArray,
              R.find(
                R.either(
                  x =>
                    R.equals(
                      normalize(x.listenurl),
                      normalize(stationController.current?.url)
                    ),
                  x =>
                    R.equals(
                      normalize(R.last(x.listenurl.split('/'))),
                      normalize(
                        R.last(stationController.current?.url.split('/'))
                      )
                    )
                )
              )
            )
          )
          .then(
            R.when(
              R.either(R.prop('title'), R.prop('artists')),
              R.pipe(
                x => `${x.artist ? x.artist + ': ' : ''}${x.title}`,
                Array,
                (xs: string[]) => {
                  if (!cancelled) setStatusStack(xs)
                }
              )
            )
          )
          .catch(() => {
            if (cancelled) return
            timeoutTime = timeoutTime * 4
            setStatusStack([defaultMessage])
          })
      }
      // set  as Interval
      timeout = setTimeout(f, timeoutTime)
    }
    let timeout = setTimeout(f, timeoutTime)
    return () => {
      cancelled = true
      setStatusStack([defaultMessage])
      clearTimeout(timeout)
    }
  }, [current, defaultMessage])
}
