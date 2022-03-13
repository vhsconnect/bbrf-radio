import React from 'react'

export default function Button({ disabled, onClick, text }) {
  return (
    <button
      disabled={disabled}
      className={disabled ? 'button-disabled' : 'button'}
      onClick={onClick}
    >
      {text}
    </button>
  )
}
