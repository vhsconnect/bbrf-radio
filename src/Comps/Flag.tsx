import React from 'react'
import { flagUrl } from '../utils/flagCache'

interface Props {
  countrycode: string
  className?: string
}

export default function Flag({ countrycode, className = 'flag' }: Props) {
  const [src, setSrc] = React.useState<string | undefined>(undefined)

  React.useEffect(() => {
    let current = true
    setSrc(undefined)
    flagUrl(countrycode).then(url => {
      if (current) setSrc(url)
    })
    return () => {
      current = false
    }
  }, [countrycode])

  return src ? <img className={className} src={src} alt={countrycode} /> : <></>
}
