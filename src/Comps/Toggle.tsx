import React from 'react'

interface Props<T extends string> {
  options: ReadonlyArray<{ value: T; text: string }>
  value: T
  onChange: (value: T) => void
}

export default function Toggle<T extends string>({
  options,
  value,
  onChange,
}: Props<T>) {
  return (
    <span className="toggle" role="group">
      {options.map(option => (
        <button
          key={option.value}
          className={option.value === value ? 'toggle-on' : 'toggle-off'}
          aria-pressed={option.value === value}
          onClick={() => onChange(option.value)}
        >
          {option.text}
        </button>
      ))}
    </span>
  )
}
