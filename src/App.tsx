import { useEffect, useMemo, useState, type ReactNode } from 'react'

type Med = { id: string; name: string; dosage: string; meal: string; times: string[]; start: string; end: string; note: string; color: string }
type Log = { status: 'taken' | 'skipped'; at: string }
type Doctor = { id: string; name: string; spec: string; phone: string }
type Relative = { id: string; name: string; rel: string; phone: string }
type ApptStatus = 'pending' | 'confirmed' | 'rescheduled' | 'cancelled'
type Appt = { id: string; at: string; place: string; dept: string; note: string; status?: ApptStatus; previousAt?: string; statusNote?: string }
type Bmi = { id: string; w: number; h: number; v: number; cat: string; at: string }
type NotifyChannel = 'app' | 'sms' | 'both'
type Data = {
  patient: string
  meds: Med[]
  logs: Record<string, Log>
  doctors: Doctor[]
  relatives: Relative[]
  appts: Appt[]
  bmis: Bmi[]
  size: string
  notify: boolean
  notifyChannel: NotifyChannel
  repeatReminder: boolean
  verifiedPhone: string
}

const uid = () => Math.random().toString(36).slice(2, 9)
const pad = (n: number) => String(n).padStart(2, '0')
const dkey = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
const today = () => dkey(new Date())
const thDate = (k: string) => new Date(k + 'T00:00').toLocaleDateString('th-TH', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })
const COLORS = ['#e9b44c', '#7fb7a4', '#e07a5f', '#8aa1d6', '#c58fc2']

const seed = (): Data => ({
  patient: 'คุณแม่สมศรี',
  size: 'normal',
  notify: true,
  notifyChannel: 'app',
  repeatReminder: true,
  verifiedPhone: '081-234-5678',
  meds: [
    { id: 'm1', name: 'ยาลดความดัน', dosage: '1 เม็ด', meal: 'หลังอาหาร', times: ['08:00'], start: today(), end: '', note: 'ทานพร้อมน้ำเปล่า', color: COLORS[0] },
    { id: 'm2', name: 'ยาเบาหวาน', dosage: '1 เม็ด', meal: 'ก่อนอาหาร', times: ['08:00', '18:00'], start: today(), end: '', note: '', color: COLORS[1] },
    { id: 'm3', name: 'แคลเซียม', dosage: '2 เม็ด', meal: 'หลังอาหาร', times: ['12:30', '21:00'], start: today(), end: '', note: '', color: COLORS[2] },
  ],
  logs: {},
  doctors: [{ id: 'd1', name: 'นพ.วิชัย ใจดี', spec: 'อายุรกรรม / โรคความดัน', phone: '021234567' }],
  relatives: [{ id: 'r1', name: 'สมชาย', rel: 'ลูกชาย', phone: '0812345678' }],
  appts: [{ id: 'a1', at: new Date(Date.now() + 5 * 864e5).toISOString().slice(0, 11) + '09:30', place: 'โรงพยาบาลศิริราช', dept: 'อายุรกรรม', note: 'งดน้ำและอาหารก่อนตรวจ 8 ชั่วโมง', status: 'confirmed' }],
  bmis: [],
})

function load(): Data {
  try {
    const s = localStorage.getItem('caredose')
    if (s) return { ...seed(), ...JSON.parse(s) }
  } catch { /* ignore */ }
  return seed()
}

type Item = { med: Med; time: string; key: string; log?: Log; status: 'taken' | 'skipped' | 'pending' | 'missed' }
const STATUS: Record<Item['status'], { label: string; cls: string }> = {
  taken: { label: 'ทานแล้ว', cls: 'bg-green-100 text-green-900 border-green-700' },
  skipped: { label: 'ข้าม', cls: 'bg-stone-200 text-stone-800 border-stone-500' },
  pending: { label: 'รอทาน', cls: 'bg-amber-100 text-amber-900 border-amber-700' },
  missed: { label: 'เลยเวลา', cls: 'bg-red-100 text-red-900 border-red-700' },
}

function itemsFor(d: Data, date: string, now = new Date()): Item[] {
  const out: Item[] = []
  for (const med of d.meds) {
    if (med.start && date < med.start) continue
    if (med.end && date > med.end) continue
    for (const time of med.times) {
      const key = `${med.id}|${date}|${time}`
      const log = d.logs[key]
      const late = new Date(`${date}T${time}`).getTime() < now.getTime()
      out.push({ med, time, key, log, status: log ? log.status : late ? 'missed' : 'pending' })
    }
  }
  return out.sort((a, b) => a.time.localeCompare(b.time) || a.med.name.localeCompare(b.med.name))
}

const btn = 'rounded-2xl px-5 font-semibold transition active:scale-[0.98] focus-visible:outline-3 focus-visible:outline-offset-2 focus-visible:outline-brand'
const primary = `${btn} bg-brand text-white hover:bg-brand-dark`
const ghost = `${btn} border-2 border-brand text-brand bg-white hover:bg-teal-50`
const danger = `${btn} border-2 border-red-700 text-red-800 bg-white hover:bg-red-50`
const field = 'w-full rounded-xl border-2 border-stone-400 bg-white px-4 focus:border-brand outline-none'

function Badge({ s }: { s: Item['status'] }) {
  return <span className={`inline-block rounded-full border-2 px-3 py-0.5 text-sm font-bold ${STATUS[s].cls}`}>{STATUS[s].label}</span>
}
function Card({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <section className={`rounded-3xl bg-white p-5 shadow-sm border border-stone-200 ${className}`}>{children}</section>
}
function H({ children }: { children: ReactNode }) {
  return <h2 className="text-[1.25rem] font-bold mb-3">{children}</h2>
}
function Label({ t, children }: { t: string; children: ReactNode }) {
  return <label className="block"><span className="block text-sm font-semibold mb-1">{t}</span>{children}</label>
}
function Modal({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50" onClick={onClose}>
      <div role="dialog" aria-modal className="w-full max-w-md max-h-[92vh] overflow-auto rounded-t-3xl sm:rounded-3xl bg-paper p-5" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-[1.3rem] font-bold">{title}</h3>
          <button className={ghost} onClick={onClose}>ปิด</button>
        </div>
        {children}
      </div>
    </div>
  )
}
const call = (p: string) => { window.location.href = `tel:${p}` }
const confirmDel = (what: string) => window.confirm(`ต้องการลบ "${what}" ใช่หรือไม่?`)

export default function App() {
  const [d, setD] = useState<Data>(load)
  const [tab, setTab] = useState<'home' | 'bmi' | 'history' | 'contacts'>('home')
  const [menu, setMenu] = useState(false)
  const [now, setNow] = useState(new Date())

  useEffect(() => { localStorage.setItem('caredose', JSON.stringify(d)) }, [d])
  useEffect(() => { document.documentElement.dataset.size = d.size }, [d.size])
  useEffect(() => { const t = setInterval(() => setNow(new Date()), 30000); return () => clearInterval(t) }, [])
  const upd = (p: Partial<Data>) => setD((x) => ({ ...x, ...p }))

  const tabs = [
    { id: 'home', label: 'หน้าหลัก', icon: 'M3 11l9-8 9 8v10h-6v-6H9v6H3z' },
    { id: 'bmi', label: 'BMI', icon: 'M4 20V10m6 10V4m6 16v-7m4 7H2' },
    { id: 'history', label: 'ประวัติ', icon: 'M12 8v5l3 2M21 12a9 9 0 11-3-6.7L21 8m0-5v5h-5' },
    { id: 'contacts', label: 'ญาติ/นัด', icon: 'M16 11a4 4 0 10-8 0 4 4 0 008 0zM4 21c0-4 4-6 8-6s8 2 8 6' },
  ] as const

  return (
    <div className="mx-auto min-h-screen max-w-xl pb-28">
      <header className="sticky top-0 z-30 flex items-center justify-between bg-brand px-5 py-3 text-white">
        <div>
          <div className="text-[1.3rem] font-bold leading-tight">CareDose</div>
          <div className="text-sm opacity-90">ยาอุ่นใจ</div>
        </div>
        <button aria-label="การตั้งค่า" onClick={() => setMenu(true)} className="flex items-center gap-2 rounded-2xl bg-white/15 px-4 font-semibold hover:bg-white/25">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M4 6h16M4 12h16M4 18h16" /></svg>
          ตั้งค่า
        </button>
      </header>

      <main className="space-y-5 p-4">
        {tab === 'home' && <Home d={d} upd={upd} now={now} />}
        {tab === 'bmi' && <BmiPage d={d} upd={upd} />}
        {tab === 'history' && <History d={d} now={now} />}
        {tab === 'contacts' && <Contacts d={d} upd={upd} now={now} />}
      </main>

      <nav className="fixed bottom-0 left-0 right-0 z-30 border-t-2 border-stone-300 bg-white">
        <div className="mx-auto grid max-w-xl grid-cols-4">
          {tabs.map((t) => (
            <button key={t.id} onClick={() => setTab(t.id)} aria-current={tab === t.id} className={`flex min-h-[64px] flex-col items-center justify-center gap-0.5 text-sm font-semibold ${tab === t.id ? 'bg-teal-50 text-brand border-t-4 border-brand' : 'text-stone-700 border-t-4 border-transparent'}`}>
              <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d={t.icon} /></svg>
              {t.label}
            </button>
          ))}
        </div>
      </nav>

      {menu && <Settings d={d} upd={upd} onClose={() => setMenu(false)} />}
    </div>
  )
}

function Settings({ d, upd, onClose }: { d: Data; upd: (p: Partial<Data>) => void; onClose: () => void }) {
  const [about, setAbout] = useState(false)
  const [changePhone, setChangePhone] = useState(false)
  const [newPhone, setNewPhone] = useState('')
  const [otpSent, setOtpSent] = useState(false)
  const [otp, setOtp] = useState('')
  const [otpError, setOtpError] = useState('')
  const sendOtp = () => {
    if (newPhone.replace(/\D/g, '').length < 9) return setOtpError('กรุณากรอกเบอร์โทรศัพท์ให้ถูกต้อง')
    setOtpError('')
    setOtpSent(true)
  }
  const verifyOtp = () => {
    if (!/^\d{6}$/.test(otp)) return setOtpError('กรุณากรอกรหัส OTP 6 หลัก')
    upd({ verifiedPhone: newPhone })
    setChangePhone(false)
    setOtpSent(false)
    setNewPhone('')
    setOtp('')
    setOtpError('')
  }
  return (
    <Modal title="ตั้งค่า" onClose={onClose}>
      <div className="space-y-5">
        <Label t="ชื่อผู้ใช้"><input className={field} value={d.patient} onChange={(e) => upd({ patient: e.target.value })} /></Label>
        <div>
          <div className="text-sm font-semibold mb-1">ขนาดตัวอักษร</div>
          <div className="grid grid-cols-3 gap-2">
            {[['normal', 'ปกติ'], ['large', 'ใหญ่'], ['xl', 'ใหญ่มาก']].map(([v, l]) => (
              <button key={v} onClick={() => upd({ size: v })} className={d.size === v ? primary : ghost}>{l}</button>
            ))}
          </div>
        </div>
        <section className="rounded-3xl border-2 border-stone-300 bg-white p-4">
          <H>การแจ้งเตือนทานยา</H>
          <label className="flex min-h-16 items-center justify-between gap-4 rounded-2xl bg-teal-50 p-4">
            <span>
              <span className="block font-bold">เปิดการแจ้งเตือน</span>
              <span className="block text-sm text-stone-600">{d.notify ? 'เปิดอยู่' : 'ปิดอยู่ อาจทำให้ลืมทานยา'}</span>
            </span>
            <input type="checkbox" className="h-8 w-8 shrink-0 accent-teal-700" style={{ minHeight: 0 }} checked={d.notify} onChange={(e) => upd({ notify: e.target.checked })} />
          </label>

          <fieldset disabled={!d.notify} className={`mt-5 space-y-5 ${d.notify ? '' : 'opacity-50'}`}>
            <div>
              <div className="mb-2 font-bold">รับการแจ้งเตือนผ่าน</div>
              <div className="grid gap-2">
                {([
                  ['app', 'ผ่านแอป', 'แจ้งเตือนบนโทรศัพท์'],
                  ['sms', 'SMS', 'ส่งข้อความไปยังเบอร์ที่ยืนยัน'],
                  ['both', 'ทั้งแอปและ SMS', 'รับทั้งสองช่องทาง'],
                ] as const).map(([value, title, detail]) => (
                  <button
                    key={value}
                    type="button"
                    className={`min-h-16 rounded-2xl border-2 p-3 text-left ${d.notifyChannel === value ? 'border-brand bg-teal-50 text-brand-dark ring-2 ring-brand ring-offset-1' : 'border-stone-300 bg-white'}`}
                    onClick={() => upd({ notifyChannel: value })}
                  >
                    <span className="block font-bold">{d.notifyChannel === value ? '✓ ' : ''}{title}</span>
                    <span className="block text-sm text-stone-600">{detail}</span>
                  </button>
                ))}
              </div>
            </div>

            <div className="rounded-2xl border-2 border-stone-300 p-4">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <div className="text-sm font-semibold text-stone-600">เบอร์รับ SMS ที่ยืนยันแล้ว</div>
                    <div className="text-[1.2rem] font-bold">{d.verifiedPhone}</div>
                  </div>
                  <span className="rounded-full border-2 border-green-700 bg-green-100 px-3 py-1 text-sm font-bold text-green-900">ยืนยันด้วย OTP แล้ว</span>
                </div>
                <p className="mt-2 text-sm text-stone-600">ใช้เบอร์เดียวกับที่ยืนยันตอนเข้าสู่ระบบ ไม่ต้องกรอกซ้ำ</p>
                {!changePhone ? (
                  <button type="button" className={`${ghost} mt-3 w-full`} onClick={() => setChangePhone(true)}>เปลี่ยนเบอร์และยืนยัน OTP</button>
                ) : (
                  <div className="mt-4 space-y-3 border-t-2 border-stone-200 pt-4">
                    <Label t="เบอร์โทรศัพท์ใหม่">
                      <input className={field} inputMode="tel" value={newPhone} onChange={(e) => { setNewPhone(e.target.value); setOtpSent(false); setOtp(''); setOtpError('') }} placeholder="เช่น 0812345678" />
                    </Label>
                    {!otpSent ? (
                      <button type="button" className={`${primary} w-full`} onClick={sendOtp}>ส่งรหัส OTP</button>
                    ) : (
                      <>
                        <div className="rounded-xl bg-teal-50 p-3 text-sm font-semibold text-brand-dark">ส่งรหัส OTP ไปยัง {newPhone} แล้ว</div>
                        <Label t="รหัส OTP 6 หลัก">
                          <input className={`${field} text-center text-[1.3rem] tracking-[0.25em]`} inputMode="numeric" maxLength={6} value={otp} onChange={(e) => { setOtp(e.target.value.replace(/\D/g, '')); setOtpError('') }} placeholder="000000" />
                        </Label>
                        <button type="button" className={`${primary} w-full`} onClick={verifyOtp}>ยืนยันและใช้เบอร์นี้</button>
                        <button type="button" className={`${ghost} w-full`} onClick={sendOtp}>ส่งรหัสอีกครั้ง</button>
                      </>
                    )}
                    {otpError && <p role="alert" className="rounded-xl bg-red-100 p-3 font-semibold text-red-900">{otpError}</p>}
                    <button type="button" className={`${ghost} w-full`} onClick={() => { setChangePhone(false); setOtpSent(false); setOtpError('') }}>ยกเลิก</button>
                  </div>
                )}
                <div className={`mt-4 rounded-xl bg-amber-50 p-3 text-amber-950 ${d.notifyChannel === 'app' ? 'opacity-75' : ''}`}>
                  <div className="text-sm font-bold">ตัวอย่างข้อความ SMS</div>
                  <p>“ถึงเวลาทานยาตามแผนแล้ว”</p>
                  <p className="mt-1 text-sm">ข้อความจะไม่แสดงชื่อยาหรือข้อมูลสุขภาพ และ SMS อาจมีค่าใช้จ่ายตามเครือข่าย</p>
                </div>
              </div>

            <label className="flex min-h-16 items-start justify-between gap-4 rounded-2xl border-2 border-stone-300 p-4">
              <span>
                <span className="block font-bold">เตือนซ้ำ 1 ครั้ง</span>
                <span className="block text-sm text-stone-600">หลังถึงเวลาทานยา 15 นาที หากยังไม่ได้บันทึก</span>
              </span>
              <input type="checkbox" className="h-8 w-8 shrink-0 accent-teal-700" style={{ minHeight: 0 }} checked={d.repeatReminder} onChange={(e) => upd({ repeatReminder: e.target.checked })} />
            </label>

            <div className="rounded-2xl border-2 border-green-700 bg-green-50 p-4 text-green-950">
              <div className="font-bold">หยุดเตือนอัตโนมัติ</div>
              <p className="mt-1 text-sm">ระบบจะหยุดแจ้งเตือนรายการนั้นทันที เมื่อกด “ทานแล้ว” หรือ “ข้ามยา”</p>
            </div>
          </fieldset>
        </section>
        <button className={`${danger} w-full`} onClick={() => { if (window.confirm('ลบข้อมูลทั้งหมดในเครื่อง และเริ่มใหม่ด้วยข้อมูลตัวอย่าง?')) { upd(seed()); onClose() } }}>จัดการข้อมูลในเครื่อง: ล้างข้อมูล</button>
        <button className={`${ghost} w-full`} onClick={() => setAbout(!about)}>เกี่ยวกับแอป</button>
        {about && <p className="text-sm">CareDose (ยาอุ่นใจ) เวอร์ชัน MVP ข้อมูลทั้งหมดเก็บในเครื่องนี้เท่านั้น ไม่มีระบบบัญชี จึงไม่มีเมนูออกจากระบบ</p>}
      </div>
    </Modal>
  )
}

function Home({ d, upd, now }: { d: Data; upd: (p: Partial<Data>) => void; now: Date }) {
  const [edit, setEdit] = useState<Med | 'new' | null>(null)
  const [detail, setDetail] = useState<Med | null>(null)
  const [bulkUndo, setBulkUndo] = useState<{ keys: string[]; time: string } | null>(null)
  const items = useMemo(() => itemsFor(d, today(), now), [d, now])
  const next = items.find((i) => i.status === 'pending') ?? items.find((i) => i.status === 'missed')
  const nextGroup = next ? items.filter((i) => i.time === next.time && i.status === next.status) : []
  const mealGroups = [...new Set(items.map((i) => i.time))].map((time) => ({ time, items: items.filter((i) => i.time === time) }))

  const mark = (it: Item, status: 'taken' | 'skipped') => upd({ logs: { ...d.logs, [it.key]: { status, at: new Date().toISOString() } } })
  const undo = (it: Item) => { const l = { ...d.logs }; delete l[it.key]; upd({ logs: l }) }
  const markMeal = (mealItems: Item[], time: string) => {
    const available = mealItems.filter((it) => !it.log && new Date(`${today()}T${it.time}`).getTime() <= now.getTime())
    if (!available.length) return
    const logs = { ...d.logs }
    const at = new Date().toISOString()
    available.forEach((it) => { logs[it.key] = { status: 'taken', at } })
    upd({ logs })
    setBulkUndo({ keys: available.map((it) => it.key), time })
  }
  const undoMeal = () => {
    if (!bulkUndo) return
    const logs = { ...d.logs }
    bulkUndo.keys.forEach((key) => delete logs[key])
    upd({ logs })
    setBulkUndo(null)
  }
  useEffect(() => {
    if (!bulkUndo) return
    const timer = window.setTimeout(() => setBulkUndo(null), 6000)
    return () => window.clearTimeout(timer)
  }, [bulkUndo])

  return (
    <>
      <section className={`rounded-3xl p-6 text-white shadow-md ${next?.status === 'missed' ? 'bg-red-800' : 'bg-brand'}`}>
        <div className="text-sm font-semibold opacity-90">{next?.status === 'missed' ? 'ยาที่เลยเวลา' : 'เวลาทานยาครั้งถัดไป'}</div>
        {next ? (
          <>
            <div className="text-[3.2rem] font-bold leading-none my-2">{next.time} น.</div>
            <div className="text-[1.1rem]">{nextGroup.map((i) => `${i.med.name} ${i.med.dosage}`).join(' • ')}</div>
          </>
        ) : (
          <div className="text-[1.5rem] font-bold my-2">{items.length ? 'ทานยาครบแล้ววันนี้' : 'วันนี้ไม่มียา'}</div>
        )}
        <div className="mt-2 text-sm opacity-90">{thDate(today())}</div>
      </section>

      <div className="flex items-center justify-between">
        <h2 className="text-[1.3rem] font-bold">ยาวันนี้</h2>
        <button className={primary} onClick={() => setEdit('new')}>+ เพิ่มยา</button>
      </div>

      {items.length === 0 && <Card>ยังไม่มียาในวันนี้ กด “เพิ่มยา” เพื่อเริ่มต้น</Card>}
      {mealGroups.map((meal) => {
        const available = meal.items.filter((it) => !it.log && new Date(`${today()}T${it.time}`).getTime() <= now.getTime())
        const future = meal.items.every((it) => new Date(`${today()}T${it.time}`).getTime() > now.getTime())
        const allRecorded = meal.items.every((it) => Boolean(it.log))
        return (
          <Card key={meal.time}>
            <div className="mb-3 flex flex-wrap items-center justify-between gap-2 border-b-2 border-stone-200 pb-3">
              <div>
                <div className="text-[1.3rem] font-bold text-brand">{meal.time} น.</div>
                <div className="text-sm font-semibold">{meal.items.length} รายการในมื้อนี้</div>
              </div>
              {allRecorded && <span className="rounded-full border-2 border-green-700 bg-green-100 px-3 py-1 text-sm font-bold text-green-900">บันทึกแล้ว</span>}
            </div>
            <div className="divide-y divide-stone-200">
              {meal.items.map((it) => (
                <div key={it.key} className="py-4 first:pt-0">
                  <div className="flex gap-4">
                    <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-2xl text-2xl font-bold text-white" style={{ background: it.med.color }}>{it.med.name.slice(0, 1)}</div>
                    <div className="min-w-0 flex-1">
                      <div className="text-[1.2rem] font-bold leading-tight break-words">{it.med.name}</div>
                      <div>{it.med.dosage}{it.med.meal ? ` • ${it.med.meal}` : ''}</div>
                      <div className="mt-1"><Badge s={it.status} />{it.log && <span className="ml-2 text-sm">เวลา {new Date(it.log.at).toLocaleTimeString('th-TH', { hour: '2-digit', minute: '2-digit' })} น.</span>}</div>
                    </div>
                  </div>
                  <div className="mt-3 grid grid-cols-2 gap-2">
                    {it.log ? (
                      <button className={`${ghost} col-span-2`} onClick={() => undo(it)}>ยกเลิกการบันทึก</button>
                    ) : (
                      <>
                        <button className={primary} onClick={() => mark(it, 'taken')}>ทานแล้ว</button>
                        <button className={ghost} onClick={() => mark(it, 'skipped')}>ข้ามยา</button>
                      </>
                    )}
                    <button className={`${ghost} col-span-2`} onClick={() => setDetail(it.med)}>ดูรายละเอียด</button>
                  </div>
                </div>
              ))}
            </div>
            {bulkUndo?.time === meal.time ? (
              <div className="mt-4 rounded-2xl border-2 border-green-700 bg-green-100 p-3 text-green-950">
                <div className="font-bold">บันทึกยามื้อนี้แล้ว</div>
                <button className={`${ghost} mt-2 w-full`} onClick={undoMeal}>ย้อนกลับ</button>
              </div>
            ) : (
              <button
                className={`${primary} mt-4 w-full disabled:border-stone-400 disabled:bg-stone-200 disabled:text-stone-600`}
                disabled={future || available.length === 0}
                onClick={() => markMeal(meal.items, meal.time)}
              >
                {future
                  ? `ยังไม่ถึงเวลา ${meal.time} น.`
                  : available.length === 0
                    ? 'มื้อนี้บันทึกครบแล้ว'
                    : available.length < meal.items.length
                      ? `ทานยาที่เหลือ (${available.length} รายการ)`
                      : `ทานครบทุกตัวในมื้อนี้ (${available.length} รายการ)`}
              </button>
            )}
          </Card>
        )
      })}

      <Card>
        <H>แพทย์ผู้ดูแล</H>
        <div className="space-y-3">
          {d.doctors.map((x) => (
            <div key={x.id} className="flex flex-wrap items-center gap-3 rounded-2xl border border-stone-200 p-3">
              <div className="min-w-0 flex-1">
                <div className="font-bold">{x.name}</div>
                <div className="text-sm break-words">{x.spec}</div>
              </div>
              <button className={`${primary} min-w-24`} onClick={() => call(x.phone)}>โทร</button>
            </div>
          ))}
          {!d.doctors.length && <p>ยังไม่มีรายชื่อแพทย์</p>}
        </div>
      </Card>

      {detail && (
        <Modal title="รายละเอียดยา" onClose={() => setDetail(null)}>
          <div className="flex flex-col items-center text-center">
            <div className="flex h-36 w-36 items-center justify-center rounded-3xl text-5xl font-bold text-white shadow-sm" style={{ background: detail.color }}>
              {detail.name.slice(0, 1)}
            </div>
            <div className="mt-4 text-[1.4rem] font-bold leading-tight break-words">{detail.name}</div>
            <div className="mt-2 text-[1.05rem] font-semibold">{detail.dosage}</div>
            <div className="mt-1">{detail.meal || 'ใช้ตามคำแนะนำของแพทย์'}</div>
            <div className="mt-1">เวลา {detail.times.join(', ')} น.</div>
          </div>
          <div className="mt-5 rounded-2xl border-2 border-amber-500 bg-amber-50 p-4">
            <div className="font-bold text-amber-950">คำเตือนและข้อควรจำ</div>
            <p className="mt-1 break-words text-amber-950">{detail.note || 'ทานยาตามขนาดและเวลาที่แพทย์กำหนด หากมีอาการผิดปกติให้ติดต่อแพทย์'}</p>
          </div>
          <p className="mt-4 text-center text-sm text-stone-600">ข้อมูลนี้เป็นแบบอ่านอย่างเดียว หากต้องการแก้ไข กรุณาติดต่อแพทย์หรือเจ้าหน้าที่</p>
        </Modal>
      )}
      {edit && <MedForm initial={edit === 'new' ? null : edit} onClose={() => setEdit(null)} onSave={(m) => { upd({ meds: d.meds.some((x) => x.id === m.id) ? d.meds.map((x) => (x.id === m.id ? m : x)) : [...d.meds, m] }); setEdit(null) }} count={d.meds.length} />}
    </>
  )
}

function MedForm({ initial, onSave, onClose, count }: { initial: Med | null; onSave: (m: Med) => void; onClose: () => void; count: number }) {
  const [m, setM] = useState<Med>(initial ?? { id: uid(), name: '', dosage: '1 เม็ด', meal: '', times: ['08:00'], start: today(), end: '', note: '', color: COLORS[count % COLORS.length] })
  const [err, setErr] = useState('')
  const set = (p: Partial<Med>) => setM({ ...m, ...p })
  const submit = () => {
    if (!m.name.trim()) return setErr('กรุณากรอกชื่อยา')
    if (!m.times.length || m.times.some((t) => !t)) return setErr('กรุณาระบุเวลาเตือน')
    if (m.end && m.end < m.start) return setErr('วันที่สิ้นสุดต้องไม่ก่อนวันที่เริ่ม')
    onSave({ ...m, name: m.name.trim(), times: [...new Set(m.times)].sort() })
  }
  return (
    <Modal title={initial ? 'แก้ไขยา' : 'เพิ่มยา'} onClose={onClose}>
      <div className="space-y-4">
        <Label t="ชื่อยา (จำเป็น)"><input className={field} value={m.name} onChange={(e) => set({ name: e.target.value })} /></Label>
        <Label t="ปริมาณ เช่น 1 เม็ด, 5 ml"><input className={field} value={m.dosage} onChange={(e) => set({ dosage: e.target.value })} /></Label>
        <div>
          <div className="text-sm font-semibold mb-1">เวลาเตือน</div>
          <div className="space-y-2">
            {m.times.map((t, i) => (
              <div key={i} className="flex gap-2">
                <input type="time" className={field} value={t} onChange={(e) => set({ times: m.times.map((x, j) => (j === i ? e.target.value : x)) })} />
                {m.times.length > 1 && <button className={danger} onClick={() => set({ times: m.times.filter((_, j) => j !== i) })}>ลบ</button>}
              </div>
            ))}
            <button className={ghost} onClick={() => set({ times: [...m.times, '12:00'] })}>+ เพิ่มเวลา</button>
          </div>
        </div>
        <Label t="ก่อน/หลังอาหาร">
          <select className={field} value={m.meal} onChange={(e) => set({ meal: e.target.value })}>
            <option value="">ไม่ระบุ</option><option>ก่อนอาหาร</option><option>หลังอาหาร</option><option>พร้อมอาหาร</option>
          </select>
        </Label>
        <div className="grid grid-cols-2 gap-3">
          <Label t="วันที่เริ่ม"><input type="date" className={field} value={m.start} onChange={(e) => set({ start: e.target.value })} /></Label>
          <Label t="วันที่สิ้นสุด"><input type="date" className={field} value={m.end} onChange={(e) => set({ end: e.target.value })} /></Label>
        </div>
        <Label t="หมายเหตุ"><textarea className={`${field} py-2`} rows={2} value={m.note} onChange={(e) => set({ note: e.target.value })} /></Label>
        {err && <p role="alert" className="rounded-xl bg-red-100 p-3 font-semibold text-red-900">{err}</p>}
        <button className={`${primary} w-full`} onClick={submit}>บันทึก</button>
      </div>
    </Modal>
  )
}

function PersonForm({ title, fields, initial, onSave, onClose, onDelete }: { title: string; fields: [string, string][]; initial: Record<string, string>; onSave: (v: Record<string, string>) => void; onClose: () => void; onDelete?: () => void }) {
  const [v, setV] = useState(initial)
  const [err, setErr] = useState('')
  return (
    <Modal title={`${onDelete ? 'แก้ไข' : 'เพิ่ม'}${title}`} onClose={onClose}>
      <div className="space-y-4">
        {fields.map(([k, l]) => (
          <Label key={k} t={l}><input className={field} inputMode={k === 'phone' ? 'tel' : undefined} value={v[k] ?? ''} onChange={(e) => setV({ ...v, [k]: e.target.value })} /></Label>
        ))}
        {err && <p role="alert" className="rounded-xl bg-red-100 p-3 font-semibold text-red-900">{err}</p>}
        <button className={`${primary} w-full`} onClick={() => (!v.name?.trim() || !v.phone?.trim() ? setErr('กรุณากรอกชื่อและเบอร์โทร') : onSave(v))}>บันทึก</button>
        {onDelete && <button className={`${danger} w-full`} onClick={onDelete}>ลบ</button>}
      </div>
    </Modal>
  )
}

const BMI_CAT = (v: number) => (v < 18.5 ? 'ต่ำกว่าเกณฑ์' : v < 25 ? 'ปกติ' : 'สูงกว่าเกณฑ์')

function BmiPage({ d, upd }: { d: Data; upd: (p: Partial<Data>) => void }) {
  const [w, setW] = useState('')
  const [h, setH] = useState('')
  const [err, setErr] = useState('')
  const last = d.bmis[0]
  const calc = () => {
    const wn = parseFloat(w), hn = parseFloat(h)
    if (!(wn > 0 && wn < 400) || !(hn > 50 && hn < 250)) return setErr('กรุณากรอกน้ำหนัก (กก.) และส่วนสูง (ซม.) ให้ถูกต้อง')
    setErr('')
    const v = Math.round((wn / (hn / 100) ** 2) * 10) / 10
    upd({ bmis: [{ id: uid(), w: wn, h: hn, v, cat: BMI_CAT(v), at: new Date().toISOString() }, ...d.bmis] })
  }
  const tone = last?.cat === 'ปกติ' ? 'bg-green-100 border-green-700 text-green-900' : 'bg-amber-100 border-amber-700 text-amber-900'
  return (
    <>
      <Card>
        <H>คำนวณ BMI</H>
        <div className="grid grid-cols-2 gap-3">
          <Label t="น้ำหนัก (กิโลกรัม)"><input className={field} inputMode="decimal" value={w} onChange={(e) => setW(e.target.value)} placeholder="เช่น 58" /></Label>
          <Label t="ส่วนสูง (เซนติเมตร)"><input className={field} inputMode="decimal" value={h} onChange={(e) => setH(e.target.value)} placeholder="เช่น 155" /></Label>
        </div>
        {err && <p role="alert" className="mt-3 rounded-xl bg-red-100 p-3 font-semibold text-red-900">{err}</p>}
        <button className={`${primary} mt-4 w-full`} onClick={calc}>คำนวณ BMI</button>
      </Card>
      {last && (
        <div className={`rounded-3xl border-2 p-6 text-center ${tone}`}>
          <div className="text-sm font-semibold">ค่า BMI ล่าสุด</div>
          <div className="text-[3.5rem] font-bold leading-none">{last.v}</div>
          <div className="text-[1.4rem] font-bold">{last.cat}</div>
        </div>
      )}
      <p className="rounded-2xl bg-white p-4 text-sm border border-stone-300">ผลลัพธ์เป็นข้อมูลเบื้องต้น ไม่ใช่การวินิจฉัยทางการแพทย์</p>
      {d.bmis.length > 0 && (
        <Card>
          <H>ประวัติ BMI</H>
          <ul className="divide-y divide-stone-200">
            {d.bmis.map((b) => (
              <li key={b.id} className="flex items-center justify-between py-2">
                <div><div className="font-bold">{b.v} • {b.cat}</div><div className="text-sm">{b.w} กก. / {b.h} ซม.</div></div>
                <div className="text-right text-sm">{new Date(b.at).toLocaleString('th-TH', { dateStyle: 'medium', timeStyle: 'short' })}</div>
              </li>
            ))}
          </ul>
        </Card>
      )}
    </>
  )
}

type CalendarMeta = { label: string; cls: string }

function CalendarPicker({ date, onChange, label = 'เลือกวันที่', dayMeta }: { date: string; onChange: (date: string) => void; label?: string; dayMeta?: (date: string) => CalendarMeta }) {
  const selected = new Date(`${date}T00:00`)
  const [view, setView] = useState(() => new Date(selected.getFullYear(), selected.getMonth(), 1))
  const year = view.getFullYear()
  const month = view.getMonth()
  const firstWeekday = new Date(year, month, 1).getDay()
  const daysInMonth = new Date(year, month + 1, 0).getDate()
  useEffect(() => {
    setView(new Date(selected.getFullYear(), selected.getMonth(), 1))
  }, [date])
  return (
    <div>
      <div className="mb-2 text-[1.05rem] font-bold">{label}</div>
      <div className="rounded-2xl border-2 border-stone-300 bg-white p-3">
        <div className="grid grid-cols-[48px_1fr_48px] items-center gap-2">
          <button className={`${ghost} px-0 text-[1.4rem]`} aria-label="เดือนก่อนหน้า" onClick={() => setView(new Date(year, month - 1, 1))}>‹</button>
          <div className="text-center text-[1.15rem] font-bold">{view.toLocaleDateString('th-TH', { month: 'long', year: 'numeric' })}</div>
          <button className={`${ghost} px-0 text-[1.4rem]`} aria-label="เดือนถัดไป" onClick={() => setView(new Date(year, month + 1, 1))}>›</button>
        </div>
        <div className="mt-3 grid grid-cols-7 gap-1 text-center text-sm font-semibold text-stone-600">
          {['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'].map((day) => <div key={day}>{day}</div>)}
        </div>
        <div className="mt-1 grid grid-cols-7 gap-1">
          {Array.from({ length: firstWeekday }, (_, i) => <div key={`blank-${i}`} />)}
          {Array.from({ length: daysInMonth }, (_, i) => i + 1).map((day) => {
            const value = `${year}-${pad(month + 1)}-${pad(day)}`
            const active = value === date
            const meta = dayMeta?.(value)
            return (
              <button
                key={day}
                aria-label={`${day} ${meta?.label || ''}${active ? ' วันที่เลือก' : ''}`}
                onClick={() => onChange(value)}
                className={`min-h-14 min-w-0 rounded-xl border-2 px-0.5 py-1 leading-tight ${active ? 'border-brand bg-brand text-white ring-2 ring-brand ring-offset-2' : meta?.cls || 'border-stone-200 bg-stone-50 text-ink hover:border-brand'}`}
              >
                <span className="block font-bold">{active ? `✓ ${day}` : day}</span>
                {meta && <span className="block text-[0.6rem] font-semibold">{meta.label}</span>}
              </button>
            )
          })}
        </div>
        <div className="mt-3 rounded-xl bg-teal-50 p-3 text-center font-bold text-brand-dark">เลือกแล้ว: {thDate(date)}</div>
      </div>
    </div>
  )
}

function DateRangePicker({ from, to, onFromChange, onToChange }: { from: string; to: string; onFromChange: (date: string) => void; onToChange: (date: string) => void }) {
  const [active, setActive] = useState<'from' | 'to'>('from')
  const choose = (date: string) => {
    if (active === 'from') {
      onFromChange(date)
      setActive('to')
    } else {
      onToChange(date)
    }
  }
  return (
    <div className="space-y-3">
      <div className="grid gap-2">
        <button className={`rounded-2xl border-2 p-3 text-left ${active === 'from' ? 'border-brand bg-teal-50 ring-2 ring-brand ring-offset-1' : 'border-stone-300 bg-white'}`} onClick={() => setActive('from')}>
          <span className="block text-sm font-semibold text-stone-600">จากวันที่</span>
          <span className="block font-bold">{new Date(`${from}T00:00`).toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: 'numeric' })}</span>
        </button>
        <button className={`rounded-2xl border-2 p-3 text-left ${active === 'to' ? 'border-brand bg-teal-50 ring-2 ring-brand ring-offset-1' : 'border-stone-300 bg-white'}`} onClick={() => setActive('to')}>
          <span className="block text-sm font-semibold text-stone-600">ถึงวันที่</span>
          <span className="block font-bold">{new Date(`${to}T00:00`).toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: 'numeric' })}</span>
        </button>
      </div>
      <CalendarPicker date={active === 'from' ? from : to} onChange={choose} label={active === 'from' ? 'เลือกวันเริ่มต้น' : 'เลือกวันสิ้นสุด'} />
      <div className={`rounded-2xl border-2 p-3 text-center ${from <= to ? 'border-teal-300 bg-teal-50 text-brand-dark' : 'border-red-500 bg-red-50 text-red-900'}`}>
        <div className="text-sm font-semibold">{from <= to ? 'ช่วงวันที่ที่เลือก' : 'วันที่สิ้นสุดต้องไม่ก่อนวันที่เริ่ม'}</div>
        {from <= to && <div className="font-bold">{thDate(from)} ถึง {thDate(to)}</div>}
      </div>
    </div>
  )
}

function History({ d, now }: { d: Data; now: Date }) {
  const [date, setDate] = useState(today())
  const [from, setFrom] = useState(today())
  const [to, setTo] = useState(today())
  const items = itemsFor(d, date, now)
  const count = (s: Item['status']) => items.filter((i) => i.status === s).length
  const daySummary = (dateValue: string) => {
    const dayItems = itemsFor(d, dateValue, now)
    if (!dayItems.length) return { label: 'ไม่มี', cls: 'bg-stone-100 text-stone-600 border-stone-300' }
    if (dayItems.some((i) => i.status === 'missed')) return { label: 'พลาด', cls: 'bg-red-100 text-red-900 border-red-500' }
    if (dayItems.some((i) => i.status === 'skipped')) return { label: 'ข้าม', cls: 'bg-blue-100 text-blue-900 border-blue-500' }
    if (dayItems.every((i) => i.status === 'taken')) return { label: 'ครบ', cls: 'bg-green-100 text-green-900 border-green-600' }
    return { label: 'รอทาน', cls: 'bg-amber-100 text-amber-900 border-amber-600' }
  }

  const exportXls = () => {
    const rows = [['วันที่', 'เวลาที่กำหนด', 'ชื่อยา', 'ปริมาณ', 'สถานะ', 'เวลาที่บันทึก', 'หมายเหตุ']]
    for (let t = new Date(from + 'T00:00'); dkey(t) <= to; t.setDate(t.getDate() + 1)) {
      for (const i of itemsFor(d, dkey(t), now)) rows.push([dkey(t), i.time, i.med.name, i.med.dosage, STATUS[i.status].label, i.log ? new Date(i.log.at).toLocaleString('th-TH') : '', i.med.note])
    }
    const esc = (s: string) => `"${s.replace(/"/g, '""')}"`
    const csv = '\uFEFF' + rows.map((r) => r.map(esc).join(',')).join('\r\n')
    const a = document.createElement('a')
    a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }))
    a.download = `caredose_${from}_${to}.csv`
    a.click()
  }

  return (
    <>
      <Card>
        <CalendarPicker date={date} onChange={setDate} label="เลือกวันที่ดูประวัติ" dayMeta={daySummary} />
        <div className="mt-4 grid grid-cols-2 gap-2 text-sm">
          <div><span className="font-bold text-green-800">ครบ</span> = ทานครบแล้ว</div>
          <div><span className="font-bold text-amber-800">รอทาน</span> = ยังไม่ถึงเวลา</div>
          <div><span className="font-bold text-red-800">พลาด</span> = เลยเวลา</div>
          <div><span className="font-bold text-blue-800">ข้าม</span> = ข้ามยา</div>
          <div className="col-span-2"><span className="font-bold text-stone-600">ไม่มี</span> = ไม่มีรายการยา</div>
        </div>
      </Card>
      <div className="grid grid-cols-4 gap-2 text-center">
        {(['taken', 'pending', 'skipped', 'missed'] as const).map((s) => (
          <div key={s} className={`rounded-2xl border-2 py-2 ${STATUS[s].cls}`}>
            <div className="text-[1.6rem] font-bold leading-none">{count(s)}</div>
            <div className="text-xs font-bold">{STATUS[s].label}</div>
          </div>
        ))}
      </div>
      {items.length === 0 && (
        <Card className="text-center">
          <div className="text-[1.15rem] font-bold">ไม่มีรายการยาในวันนี้</div>
          <p className="mt-1 text-stone-600">เลือกวันอื่นจากปฏิทินเพื่อดูประวัติ</p>
        </Card>
      )}
      {items.map((i) => (
        <Card key={i.key}>
          <div className="flex items-start justify-between gap-2">
            <div>
              <div className="text-[1.15rem] font-bold">{i.med.name}</div>
              <div className="text-sm">{i.med.dosage}</div>
            </div>
            <Badge s={i.status} />
          </div>
          <div className="mt-3 grid gap-2 rounded-2xl bg-stone-50 p-3 sm:grid-cols-2">
            <div><span className="block text-sm font-semibold text-stone-600">เวลาที่กำหนด</span><span className="font-bold">{i.time} น.</span></div>
            <div><span className="block text-sm font-semibold text-stone-600">เวลาที่ทานจริง</span><span className="font-bold">{i.log ? new Date(i.log.at).toLocaleTimeString('th-TH', { hour: '2-digit', minute: '2-digit' }) + ' น.' : 'ยังไม่มีข้อมูล'}</span></div>
          </div>
          {i.med.note && <div className="mt-2 text-sm"><span className="font-semibold">หมายเหตุ:</span> {i.med.note}</div>}
        </Card>
      ))}
      <Card>
        <H>Export Excel</H>
        <DateRangePicker from={from} to={to} onFromChange={setFrom} onToChange={setTo} />
        <button className={`${primary} mt-4 w-full disabled:opacity-50`} disabled={!from || !to || from > to} onClick={exportXls}>Export Excel</button>
        <p className="mt-2 text-sm">ไฟล์เปิดได้ด้วย Excel (ต้นแบบนี้ส่งออกเป็น .csv)</p>
      </Card>
    </>
  )
}

function Contacts({ d, upd, now }: { d: Data; upd: (p: Partial<Data>) => void; now: Date }) {
  const [rel, setRel] = useState<Relative | 'new' | null>(null)
  const items = itemsFor(d, today(), now)
  const done = items.filter((i) => i.status === 'taken').length
  const appts = [...d.appts].sort((a, b) => a.at.localeCompare(b.at))
  return (
    <>
      <Card>
        <div className="text-sm font-semibold">ผู้ป่วย</div>
        <div className="text-[1.4rem] font-bold">{d.patient}</div>
        <div className="mt-2 rounded-xl bg-teal-50 p-3 font-semibold text-brand-dark">วันนี้ ทานแล้ว {done} จาก {items.length} รายการ</div>
      </Card>

      <Card>
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <H>ญาติฉุกเฉิน</H>
          <button className={ghost} onClick={() => setRel('new')}>+ เพิ่มญาติ</button>
        </div>
        <div className="space-y-4">
          {d.relatives.map((r) => (
            <div key={r.id} className="rounded-2xl border-2 border-stone-200 p-4">
              <div className="min-w-0">
                <div className="text-[1.15rem] font-bold break-words">{r.name}</div>
                <div className="mt-1 text-stone-600">{r.rel}</div>
                <div className="mt-1 font-semibold break-all">{r.phone}</div>
              </div>
              <div className="mt-4 grid grid-cols-2 gap-2">
                <button className={primary} onClick={() => call(r.phone)}>โทรหาญาติ</button>
                <button className={ghost} onClick={() => setRel(r)}>แก้ไข</button>
              </div>
            </div>
          ))}
          {!d.relatives.length && <p>ยังไม่มีรายชื่อญาติ</p>}
        </div>
      </Card>

      <Card>
        <H>นัดหมายแพทย์</H>
        <p className="mb-4 text-sm text-stone-600">นัดหมายกำหนดโดยแพทย์หรือเจ้าหน้าที่</p>
        <div className="space-y-4">
          {appts.map((a) => {
            const past = new Date(a.at) < now
            const status = a.status ?? 'pending'
            const statusStyle: Record<ApptStatus, { label: string; cls: string }> = {
              pending: { label: 'รอนัด', cls: 'border-amber-700 bg-amber-100 text-amber-900' },
              confirmed: { label: 'ยืนยันแล้ว', cls: 'border-green-700 bg-green-100 text-green-900' },
              rescheduled: { label: 'เลื่อนนัด', cls: 'border-orange-700 bg-orange-100 text-orange-900' },
              cancelled: { label: 'ยกเลิก', cls: 'border-red-700 bg-red-100 text-red-900' },
            }
            const currentStatus = statusStyle[status]
            return (
              <div key={a.id} className={`rounded-2xl border-2 p-4 ${status === 'cancelled' ? 'border-red-500 bg-red-50' : past ? 'border-stone-300 bg-stone-100' : 'border-brand bg-teal-50'}`}>
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="text-sm font-semibold text-stone-600">สถานะนัดหมาย</div>
                  <span className={`rounded-full border-2 px-3 py-1 text-sm font-bold ${currentStatus.cls}`}>{currentStatus.label}</span>
                </div>
                {past && status !== 'cancelled' && <div className="mt-2 text-sm font-bold text-stone-600">นัดนี้ผ่านมาแล้ว</div>}
                {status === 'rescheduled' && a.previousAt && (
                  <div className="mt-3 rounded-xl border border-orange-300 bg-orange-50 p-3 text-orange-950">
                    <div className="text-sm font-semibold">กำหนดเดิม</div>
                    <div className="line-through">{new Date(a.previousAt).toLocaleString('th-TH', { dateStyle: 'long', timeStyle: 'short' })} น.</div>
                  </div>
                )}
                <div className="mt-3 text-[1.1rem] font-bold leading-snug">{new Date(a.at).toLocaleDateString('th-TH', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}</div>
                <div className={`mt-1 text-[1.2rem] font-bold ${status === 'cancelled' ? 'text-red-800' : 'text-brand'}`}>{new Date(a.at).toLocaleTimeString('th-TH', { hour: '2-digit', minute: '2-digit' })} น.</div>
                <div className="mt-3 rounded-xl bg-white/70 p-3">
                  <div><span className="font-semibold">สถานที่:</span> {a.place}</div>
                  <div className="mt-1"><span className="font-semibold">แผนก:</span> {a.dept || 'ไม่ระบุ'}</div>
                  {a.note && <div className="mt-2 border-t border-stone-300 pt-2"><span className="font-semibold">หมายเหตุ:</span> {a.note}</div>}
                </div>
                {(status === 'rescheduled' || status === 'cancelled') && (
                  <div className={`mt-3 rounded-xl p-3 ${status === 'cancelled' ? 'bg-red-100 text-red-950' : 'bg-orange-100 text-orange-950'}`}>
                    <span className="font-semibold">รายละเอียดล่าสุด:</span> {a.statusNote || (status === 'cancelled' ? 'นัดหมายนี้ถูกยกเลิกโดยแพทย์หรือเจ้าหน้าที่' : 'วันและเวลานัดด้านบนเป็นกำหนดล่าสุด')}
                  </div>
                )}
              </div>
            )
          })}
          {!appts.length && <p>ยังไม่มีนัดหมาย</p>}
        </div>
      </Card>

      {rel && (
        <PersonForm title="ญาติ" fields={[['name', 'ชื่อ'], ['rel', 'ความสัมพันธ์'], ['phone', 'เบอร์โทร']]} initial={rel === 'new' ? { id: uid(), name: '', rel: '', phone: '' } : rel}
          onClose={() => setRel(null)}
          onDelete={rel !== 'new' ? () => { if (confirmDel(rel.name)) { upd({ relatives: d.relatives.filter((x) => x.id !== rel.id) }); setRel(null) } } : undefined}
          onSave={(v) => { const x = v as Relative; upd({ relatives: d.relatives.some((y) => y.id === x.id) ? d.relatives.map((y) => (y.id === x.id ? x : y)) : [...d.relatives, x] }); setRel(null) }} />
      )}
    </>
  )
}
