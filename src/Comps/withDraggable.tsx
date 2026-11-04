import React, { useRef } from 'react'
import Draggable from 'react-draggable'
import type { Position } from '../utils/favLayout'

export const GRID_CELL = 16

type DragProps = {
  position: Position
  z: number
  onMove: (position: Position) => void
}

const withDraggable =
  <P extends object>(Child: React.ComponentType<P>, bounds?: string) =>
  ({ position, z, onMove, ...props }: P & DragProps) => {
    const nodeRef = useRef<HTMLDivElement>(null)
    const dragged = useRef(false)

    return (
      <Draggable
        nodeRef={nodeRef}
        grid={[GRID_CELL, GRID_CELL]}
        bounds={bounds}
        position={position}
        onStart={() => {
          dragged.current = false
        }}
        onDrag={() => {
          dragged.current = true
        }}
        onStop={(_, { x, y }) => {
          if (dragged.current) onMove({ x, y })
        }}
      >
        <div
          ref={nodeRef}
          className="draggable"
          style={{ '--z': z } as React.CSSProperties}
          // releasing a drag over the child would otherwise fire its onClick
          onClickCapture={e => {
            if (dragged.current) {
              e.stopPropagation()
              dragged.current = false
            }
          }}
        >
          <Child {...(props as P)} />
        </div>
      </Draggable>
    )
  }

export default withDraggable
