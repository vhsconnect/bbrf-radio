import React from 'react'

interface Props {
  alternateColor?: string | boolean
  disabled: boolean
  onClick: () => void
  text: string
  extraSyle?: React.CSSProperties
}

export default function Button({
  alternateColor,
  disabled,
  onClick,
  text,
  extraSyle,
}: Props) {
  const colorStyle =
    typeof alternateColor === 'string'
      ? { color: alternateColor, border: `solid ${alternateColor}` }
      : alternateColor
      ? { color: 'seagreen', border: 'solid seagreen' }
      : {}

  return (
    <button
      style={{
        cursor: 'pointer',
        ...colorStyle,
        ...(extraSyle ? extraSyle : {}),
      }}
      disabled={disabled}
      className={disabled ? 'button-disabled' : 'button'}
      onClick={onClick}
    >
      {text}
    </button>
  )
}
