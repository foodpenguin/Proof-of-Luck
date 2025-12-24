'use client';

import React, { useRef, useEffect, useState } from 'react';
import styled from 'styled-components';

const MapWrapper = styled.div`
  width: 100%;
  max-width: 500px;
  aspect-ratio: 1;
  position: relative;
  border: 4px solid ${({ theme }) => theme.colors.black};
  background-color: #1a1a1a;
  cursor: crosshair;
  margin: 0 auto;
`;

const Canvas = styled.canvas`
  width: 100%;
  height: 100%;
  display: block;
`;

const Coordinates = styled.div`
  font-family: ${({ theme }) => theme.fonts.mono};
  text-align: center;
  margin-top: 1rem;
  font-weight: bold;
  font-size: 0.9rem;
`;

interface BattleMapProps {
  onSelect?: (x: number, y: number) => void;
}

export const BattleMap = ({ onSelect }: BattleMapProps) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [selected, setSelected] = useState<{x: number, y: number} | null>(null);
  const [hover, setHover] = useState<{x: number, y: number} | null>(null);

  // Game Constants
  const MAP_SIZE = 1000;
  const SAFE_RADIUS = 500; // Initial radius
  const CENTER = MAP_SIZE / 2;

  const draw = () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Clear
    ctx.fillStyle = '#1a1a1a';
    ctx.fillRect(0, 0, MAP_SIZE, MAP_SIZE);

    // Draw Grid (every 100 units)
    ctx.strokeStyle = '#333';
    ctx.lineWidth = 2;
    for (let i = 0; i <= MAP_SIZE; i += 100) {
      ctx.beginPath();
      ctx.moveTo(i, 0);
      ctx.lineTo(i, MAP_SIZE);
      ctx.stroke();
      
      ctx.beginPath();
      ctx.moveTo(0, i);
      ctx.lineTo(MAP_SIZE, i);
      ctx.stroke();
    }

    // Draw Safe Zone (Circle)
    ctx.beginPath();
    ctx.arc(CENTER, CENTER, SAFE_RADIUS, 0, Math.PI * 2);
    ctx.strokeStyle = '#00ff00'; // Green
    ctx.lineWidth = 4;
    ctx.stroke();
    ctx.fillStyle = 'rgba(0, 255, 0, 0.1)';
    ctx.fill();

    // Draw Selected Point
    if (selected) {
      ctx.beginPath();
      ctx.arc(selected.x, selected.y, 10, 0, Math.PI * 2);
      ctx.fillStyle = '#ff0000'; // Red
      ctx.fill();
      ctx.strokeStyle = '#fff';
      ctx.lineWidth = 2;
      ctx.stroke();

      // Crosshair
      ctx.beginPath();
      ctx.moveTo(selected.x - 15, selected.y);
      ctx.lineTo(selected.x + 15, selected.y);
      ctx.moveTo(selected.x, selected.y - 15);
      ctx.lineTo(selected.x, selected.y + 15);
      ctx.stroke();
    }
    
    // Draw Hover Point (if not selected)
    if (hover && !selected) {
        ctx.beginPath();
        ctx.arc(hover.x, hover.y, 5, 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(255, 255, 255, 0.5)';
        ctx.fill();
    }
  };

  useEffect(() => {
    draw();
  }, [selected, hover]);

  const handleInteraction = (e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const rect = canvas.getBoundingClientRect();
    let clientX, clientY;

    if ('touches' in e) {
        // @ts-ignore
        clientX = e.touches[0].clientX;
        // @ts-ignore
        clientY = e.touches[0].clientY;
    } else {
        clientX = (e as React.MouseEvent).clientX;
        clientY = (e as React.MouseEvent).clientY;
    }

    const scaleX = MAP_SIZE / rect.width;
    const scaleY = MAP_SIZE / rect.height;

    const x = Math.floor((clientX - rect.left) * scaleX);
    const y = Math.floor((clientY - rect.top) * scaleY);

    // Clamp
    const clampedX = Math.max(0, Math.min(MAP_SIZE - 1, x));
    const clampedY = Math.max(0, Math.min(MAP_SIZE - 1, y));

    return { x: clampedX, y: clampedY };
  };

  const handleClick = (e: React.MouseEvent<HTMLCanvasElement>) => {
    const coords = handleInteraction(e);
    if (coords) {
        setSelected(coords);
        if (onSelect) onSelect(coords.x, coords.y);
    }
  };
  
  const handleMouseMove = (e: React.MouseEvent<HTMLCanvasElement>) => {
      const coords = handleInteraction(e);
      if (coords) setHover(coords);
  };
  
  const handleMouseLeave = () => {
      setHover(null);
  };

  return (
    <div>
      <MapWrapper>
        <Canvas 
            ref={canvasRef} 
            width={MAP_SIZE} 
            height={MAP_SIZE}
            onClick={handleClick}
            onMouseMove={handleMouseMove}
            onMouseLeave={handleMouseLeave}
        />
      </MapWrapper>
      <Coordinates>
        COORD: {selected ? `[${selected.x}, ${selected.y}]` : hover ? `[${hover.x}, ${hover.y}]` : 'HOVER TO SELECT'}
      </Coordinates>
    </div>
  );
};
