import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Centro de Operaciones | CBTA 241',
  description: 'Administración segura del Portal Institucional CBTA 241',
  robots: { index: false, follow: false },
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="es-MX">
      <body>{children}</body>
    </html>
  )
}
