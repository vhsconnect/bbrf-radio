import { useEffect } from 'react'
import * as R from 'ramda'
import type { RadioInterface } from '../types'
import type { Api } from '../Comps/Main'

interface Props {
  stationController: RadioInterface
  current: HTMLAudioElement
  defaultMessage: string
  setStatusStack: (xs: string[]) => void
  api: Api
}

export default ({
  stationController,
  current,
  defaultMessage,
  setStatusStack,
  api,
}: Props) => {
  useEffect(() => {
    let timeoutTime = 10 * 1000

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
            R.replace(/\?.*/, ''), // remove cache buster
            R.replace(':80', ''),
            R.replace('https', 'http')
          )
        )

        const icecastTitle = () =>
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
              R.ifElse(
                R.either(R.prop('title'), R.prop('artists')),
                x => `${x.artist ? x.artist + ': ' : ''}${x.title}`,
                R.always(undefined)
              )
            )
            .catch(() => undefined)

        icecastTitle()
          .then(
            title =>
              title ?? api.nowPlaying(stationController.current!.stationuuid)
          )
          .then(title => {
            if (!title) throw new Error('no track info')
            setStatusStack([title])
          })
          .catch(() => {
            timeoutTime = timeoutTime * 4
            setStatusStack([defaultMessage])
          })
      }
      // set  as Interval
      timeout = setTimeout(f, timeoutTime)
    }
    let timeout = setTimeout(f, timeoutTime)
    return () => {
      setStatusStack([defaultMessage])
      clearTimeout(timeout)
    }
  }, [current, defaultMessage])
}
