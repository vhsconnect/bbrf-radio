import { useEffect } from 'react'
import * as R from 'ramda'

export default ({
  stationController,
  current,
  defaultMessage,
  setTrackInfo,
}) => {
  useEffect(() => {
    let timeoutTime = 10 * 1000

    const f = () => {
      if (stationController.current) {
        const url = stationController.current.url

        const maybeXsl = R.pipe(
          R.split('/'),
          R.dropLast(1),
          R.join('/'),
          R.flip(R.concat)('/status-json.xsl')
        )
        const maybeXsl2 = R.pipe(
          R.split('/'),
          R.dropLast(2),
          R.join('/'),
          R.flip(R.concat)('/status-json.xsl')
        )

        const normalize = R.pipe(
          R.replace(':80', ''),
          R.replace('https', 'http')
        )

        Promise.allSettled([fetch(maybeXsl(url), fetch(maybeXsl2(url)))])
          .then(results =>
            results.filter(x => x.status === 'fulfilled').map(x => x.value)
          )
          .then(R.head)
          .then(x => x.json())
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
                setTrackInfo
              )
            )
          )
          .catch(() => {
            timeoutTime = timeoutTime * 4
            setTrackInfo(null)
          })
      }
      // set  as Interval
      timeout = setTimeout(f, timeoutTime)
    }
    let timeout = setTimeout(f, timeoutTime)
    return () => {
      clearTimeout(timeout)
    }
  }, [current, defaultMessage])
}
