import React from 'react'

export default function Flag({ countrycode }) {
  const [active, setActive] = React.useState(true)
  React.useEffect(() => {
    setActive(true)
  }, [countrycode])

  return (
    active && (
      <img
        className="flag"
        src={`https://raw.githubusercontent.com/hampusborgos/country-flags/main/svg/${countrycode.toLowerCase()}.svg`}
        onError={() => {
          setActive(false)
        }}
      />
    )
  )
}
