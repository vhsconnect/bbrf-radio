import React from 'react'

interface Props {
  alternateColor?: string | boolean
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
  const colorStyle =
    typeof alternateColor === 'string'
      ? { color: alternateColor, border: `solid ${alternateColor}` }
      : alternateColor
      ? { color: 'seagreen', border: 'solid seagreen' }
      : {}

  return (
    <button
      style={{ cursor: 'pointer', ...colorStyle }}
      disabled={disabled}
      className={disabled ? 'button-disabled' : 'button'}
      onClick={onClick}
    >
      {text}
    </button>
  )
}
