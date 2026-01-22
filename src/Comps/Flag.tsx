import React from 'react'

interface Props {
  countrycode: string
}

export default function Flag({ countrycode }: Props) {
  const [active, setActive] = React.useState(true)
  React.useEffect(() => {
    setActive(true)
  }, [countrycode])

  return active ? (
    <img
      className="flag"
      src={`https://raw.githubusercontent.com/hampusborgos/country-flags/main/svg/${countrycode.toLowerCase()}.svg`}
      onError={() => {
        setActive(false)
      }}
    />
  ) : (
    <></>
  )
}
