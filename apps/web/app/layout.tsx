import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'CBTA 241 | Portal Institucional',
  description: 'Portal Digital Institucional del CBTA 241',
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="es-MX"><body>{children}</body></html>
}
