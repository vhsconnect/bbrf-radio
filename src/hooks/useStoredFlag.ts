import { useState } from 'react'

const read = (key: string, fallback: boolean): boolean => {
  try {
    const stored = localStorage.getItem(key)
    return stored === null ? fallback : stored === '1'
  } catch {
    return fallback
  }
}

const write = (key: string, value: boolean) => {
  try {
    localStorage.setItem(key, value ? '1' : '0')
  } catch {
    // storage blocked: the flag still holds for this page load
  }
}

const useStoredFlag = (
  key: string,
  fallback: boolean
): readonly [boolean, (value: boolean) => void] => {
  const [flag, setFlag] = useState(() => read(key, fallback))

  const update = (value: boolean) => {
    write(key, value)
    setFlag(value)
  }

  return [flag, update] as const
}

export default useStoredFlag
