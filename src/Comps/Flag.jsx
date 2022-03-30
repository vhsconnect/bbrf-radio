import React from 'react'

export default function Flag({ countrycode }) {
  return (
    <img className='flag'
      src={`https://raw.githubusercontent.com/hampusborgos/country-flags/main/svg/${countrycode.toLowerCase()}.svg`}
    />
  )
}
