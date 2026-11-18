import React from 'react'

interface Props {
  checked: boolean
  onChange: (checked: boolean) => void
  text: string
  title?: string
  disabled?: boolean
}

export default function Checkbox({
  checked,
  onChange,
  text,
  title,
  disabled = false,
}: Props) {
  return (
    <label
      className={disabled ? 'checkbox disabled' : 'checkbox'}
      title={title}
    >
      <input
        type="checkbox"
        checked={checked}
        disabled={disabled}
        onChange={e => onChange(e.target.checked)}
      />
      {text}
    </label>
  )
}
