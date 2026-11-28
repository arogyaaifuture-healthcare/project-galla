import QRCode from 'qrcode'
import { useEffect, useState } from 'react'
/** Draws a QR code for any text (here: the UPI payment link). Never blank: shows the text link if drawing fails. */
export default function Qr({ value, size = 220 }: { value: string; size?: number }) {
  const [src, setSrc] = useState<string | null>(null)
  const [failed, setFailed] = useState(false)
  useEffect(() => {
    let live = true
    QRCode.toDataURL(value, { width: size * 2, margin: 2, errorCorrectionLevel: 'M' }).then((u) => live && setSrc(u)).catch(() => live && setFailed(true))
    return () => { live = false }
  }, [value, size])
  if (failed) return <p role="alert" className="alert">Could not draw the QR code. Use the “Open in UPI app” button instead.</p>
  if (!src) return <div className="qr-skeleton" style={{ width: size, height: size }} aria-label="Loading QR code" />
  return <img src={src} width={size} height={size} alt="UPI payment QR code" className="qr" />
}
