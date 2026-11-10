import React from 'react'

interface Props {
  checked: boolean
  onChange: (checked: boolean) => void
  text: string
  title?: string
}

export default function Checkbox({ checked, onChange, text, title }: Props) {
  return (
    <label className="checkbox" title={title}>
      <input
        type="checkbox"
        checked={checked}
        onChange={e => onChange(e.target.checked)}
      />
      {text}
    </label>
  )
}
