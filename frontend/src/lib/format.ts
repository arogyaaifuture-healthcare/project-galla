export const rupees = (s: string) => '₹' + Number(s).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
export const day = (iso?: string | null) => (iso ? new Date(iso).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' }) : '—')
export const when = (iso: string) => new Date(iso).toLocaleString('en-IN', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })
