import * as R from 'ramda'
const MONTH_MAP = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
]
export const easyDate = () =>
  `${
    MONTH_MAP[new Date().getMonth()]
  } ${new Date().getDate()}, ${new Date().getFullYear()}, ${new Date().getHours()}:${new Date().getMinutes()}:00`

export const toUnixTimestamp = date => Math.floor(date.getTime() / 1000)

export const toHumanReadableDate = unixTimestamp =>
  R.take(16, new Date(unixTimestamp * 1000).toISOString()) + 'UTC'
