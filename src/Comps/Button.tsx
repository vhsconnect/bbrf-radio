import React from 'react'

interface Props {
  alternateColor?: boolean
  disabled: boolean
  onClick: () => void
  text: string
}

export default function Button({
  alternateColor,
  disabled,
  onClick,
  text,
}: Props) {
  return (
    <button
      style={{
        cursor: 'pointer',
        ...(alternateColor
          ? { color: 'seagreen', border: 'solid seagreen' }
          : {}),
      }}
      disabled={disabled}
      className={disabled ? 'button-disabled' : 'button'}
      onClick={onClick}
    >
      {text}
    </button>
  )
}
