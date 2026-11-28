import { Canvas, useFrame } from '@react-three/fiber'
import { Float, MeshDistortMaterial } from '@react-three/drei'
import { useRef } from 'react'
import type { Mesh } from 'three'

function Coin({ x, y, s }: { x: number; y: number; s: number }) {
  const m = useRef<Mesh>(null)
  useFrame((_, d) => { if (m.current) m.current.rotation.y += d * 0.8 })
  return (
    <Float speed={1.6} rotationIntensity={0.6} floatIntensity={1.2}>
      <mesh ref={m} position={[x, y, 0]} scale={s} rotation={[Math.PI / 2.4, 0, 0]}>
        <cylinderGeometry args={[1, 1, 0.16, 48]} />
        <meshStandardMaterial color="#f5b942" metalness={0.9} roughness={0.25} />
      </mesh>
    </Float>
  )
}
export default function Hero3D() {
  return (
    <Canvas dpr={[1, 1.5]} camera={{ position: [0, 0, 6], fov: 45 }} frameloop="always" aria-hidden>
      <ambientLight intensity={0.7} />
      <directionalLight position={[3, 4, 5]} intensity={2} />
      <Float speed={1.2} floatIntensity={0.8}>
        <mesh scale={1.6}><icosahedronGeometry args={[1, 6]} />
          <MeshDistortMaterial color="#7c5cff" distort={0.35} speed={1.6} roughness={0.2} metalness={0.4} />
        </mesh>
      </Float>
      <Coin x={-2.6} y={1.1} s={0.6} /><Coin x={2.7} y={-0.9} s={0.8} /><Coin x={2.2} y={1.6} s={0.4} />
    </Canvas>
  )
}
