import React from 'react'

export default function Button({ alternateColor, disabled, onClick, text }) {
  return (
    <button
      style={{
        cursor: 'pointer',
        ...(alternateColor ? { color: 'seagreen', border:'solid seagreen' } : {}),
      }}
      disabled={disabled}
      className={disabled ? 'button-disabled' : 'button'}
      onClick={onClick}
    >
      {text}
    </button>
  )
}
