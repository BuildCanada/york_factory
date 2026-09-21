export const MAX_CLIP_SECONDS = 30 * 60

export function clamp(value, minimum, maximum) {
  return Math.min(Math.max(value, minimum), maximum)
}

export function formatTimecode(value) {
  const seconds = Number(value)
  if (!Number.isFinite(seconds) || seconds < 0) return "00:00:00.000"

  const milliseconds = Math.round(seconds * 1000)
  const hours = Math.floor(milliseconds / 3_600_000)
  const minutes = Math.floor((milliseconds % 3_600_000) / 60_000)
  const wholeSeconds = Math.floor((milliseconds % 60_000) / 1000)
  const remainder = milliseconds % 1000
  return [hours, minutes, wholeSeconds].map(part => String(part).padStart(2, "0")).join(":") +
    `.${String(remainder).padStart(3, "0")}`
}

export function parseTimecode(value) {
  const text = String(value ?? "").trim()
  if (!text) return null
  if (/^\d+(?:\.\d{1,3})?$/.test(text)) {
    const result = Number(text)
    return Number.isFinite(result) ? result : null
  }

  const parts = text.split(":")
  if (parts.length !== 2 && parts.length !== 3) return null
  if (!parts.every((part, index) => index === parts.length - 1 ? /^\d+(?:\.\d{1,3})?$/.test(part) : /^\d+$/.test(part))) return null
  const seconds = Number(parts.at(-1)), minutes = Number(parts.at(-2)), hours = parts.length === 3 ? Number(parts[0]) : 0
  if (seconds >= 60 || (parts.length === 3 && minutes >= 60)) return null
  const result = hours * 3600 + minutes * 60 + seconds
  return Number.isFinite(result) ? result : null
}

export function overlappingGap(start, end, gaps = []) {
  return gaps.find(gap => Array.isArray(gap) && gap.length >= 2 && Number(gap[0]) < end && Number(gap[1]) > start)
}

export function validateRange(start, end, { availableEnd, gaps = [], maximum = MAX_CLIP_SECONDS } = {}) {
  if (!Number.isFinite(start) || !Number.isFinite(end)) return "Enter valid in and out timecodes."
  if (start < 0) return "The in point cannot be before the recording starts."
  if (end <= start) return "Choose an out point after the in point."
  if (end - start > maximum) return "Clips can be no longer than 30 minutes."
  if (Number.isFinite(availableEnd) && end > availableEnd) return "The out point is beyond processed footage."
  if (overlappingGap(start, end, gaps)) return "The selection crosses missing footage. Choose a range on one side of the gap."
  return null
}

export function timelinePercent(value, start, end) {
  if (!Number.isFinite(value) || !Number.isFinite(start) || !Number.isFinite(end) || end <= start) return 0
  return clamp(((value - start) / (end - start)) * 100, 0, 100)
}

export function withSelectionParams(href, base, start, end) {
  if (!href || href.startsWith("#")) return null
  try {
    const url = new URL(href, base)
    if (url.protocol !== "http:" && url.protocol !== "https:") return null
    url.searchParams.set("clip_start", start)
    url.searchParams.set("clip_end", end)
    return url.toString()
  } catch {
    return null
  }
}
