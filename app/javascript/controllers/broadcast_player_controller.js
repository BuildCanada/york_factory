import { Controller } from "@hotwired/stimulus"
import { clamp, formatTimecode, parseTimecode, timelinePercent, validateRange, withSelectionParams } from "controllers/broadcast_clip_utils"

export default class extends Controller {
  static targets = [
    "video", "start", "end", "error", "selection", "startTimecode", "endTimecode",
    "timeline", "selectionRange", "playhead", "viewportLabel", "currentTime", "duration",
    "loop", "previewButton", "playButton", "rate", "title", "exportMode", "subtitleChoice", "submit"
  ]
  static values = {
    source: String,
    origin: Number,
    seek: Number,
    recordingId: String,
    availableEnd: Number,
    windowEnd: Number,
    gaps: Array,
    rate: { type: Number, default: 1 }
  }

  async connect() {
    this.connected = true
    this.listenerController = new AbortController()
    this.viewportStart = this.originValue
    this.viewportEnd = this.windowEndValue > this.originValue ? this.windowEndValue : Math.max(this.originValue + 1, this.availableEndValue)
    this.restoreDraft()
    this.selectionChanged({ persist: false })
    this.zoomNarrowInitialSelection()
    this.installPersistentFieldListeners()
    this.installTimecodeListeners()
    document.addEventListener("keydown", event => this.keyboardShortcut(event), { signal: this.listenerController.signal })
    if (!this.hasVideoTarget) return
    const video = this.videoTarget
    this.loaded = () => {
      video.currentTime = clamp(this.seekValue, 0, Number.isFinite(video.duration) ? video.duration : this.seekValue)
      video.playbackRate = this.rateValue
      this.updatePlaybackDisplay()
      if (new URL(window.location.href).searchParams.get("preview_selection") === "1") {
        this.clearPreviewQuery()
        this.startRangePreview()
      }
    }
    video.addEventListener("loadedmetadata", this.loaded, { once: true, signal: this.listenerController.signal })
    video.addEventListener("timeupdate", () => this.timeUpdated(), { signal: this.listenerController.signal })
    video.addEventListener("play", () => this.updatePlayButton(), { signal: this.listenerController.signal })
    video.addEventListener("pause", () => this.updatePlayButton(), { signal: this.listenerController.signal })
    video.addEventListener("ratechange", () => this.updateRate(), { signal: this.listenerController.signal })
    if (video.canPlayType("application/vnd.apple.mpegurl")) {
      video.src = this.sourceValue
    } else {
      try {
        const { default: Hls } = await import("hls.js")
        if (!this.connected) return
        if (!Hls.isSupported()) throw new Error("HLS unavailable")
        this.hls = new Hls({ enableWorker: true })
        this.hls.loadSource(this.sourceValue)
        this.hls.attachMedia(video)
        this.hls.on(Hls.Events.ERROR, (_event, data) => {
          if (data.fatal && this.hasErrorTarget) this.errorTarget.textContent = "Playback could not load. Refresh this window or check capture health."
        })
      } catch {
        if (this.connected && this.hasErrorTarget) this.errorTarget.textContent = "The HLS player could not load in this browser."
      }
    }
  }

  disconnect() {
    this.connected = false
    this.listenerController?.abort()
    this.cancelPreviewFrameMonitor()
    this.hls?.destroy()
    if (this.hasVideoTarget) {
      this.videoTarget.pause()
      this.videoTarget.removeAttribute("src")
      this.videoTarget.load()
    }
  }

  markStart() { if (this.hasVideoTarget) this.setBound("start", this.recordingTime) }
  markEnd() { if (this.hasVideoTarget) this.setBound("end", this.recordingTime) }

  playPause() {
    if (!this.hasVideoTarget) return
    if (this.videoTarget.paused) this.videoTarget.play().catch(() => {})
    else this.videoTarget.pause()
  }

  skip(event) {
    const seconds = Number(event.currentTarget?.dataset.seconds ?? event.params?.seconds)
    if (Number.isFinite(seconds)) this.seekBy(seconds)
  }

  rateChanged(event) {
    const rate = Number(event.currentTarget?.value)
    if (!this.hasVideoTarget || !Number.isFinite(rate) || rate < 0.25 || rate > 4) return
    this.videoTarget.playbackRate = rate
    this.rateValue = rate
  }
  async loadCues(event) {
    const button = event.currentTarget
    const results = button.nextElementSibling
    button.disabled = true
    results.textContent = "Loading subtitle times…"
    try {
      const response = await fetch(button.dataset.url, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error("Subtitle request failed")
      const { cues } = await response.json()
      results.replaceChildren()
      if (!cues.length) results.textContent = "No subtitle cues available for this segment."
      for (const cue of cues) {
        const row = document.createElement("div")
        row.className = "broadcast-cue"
        const timing = document.createElement("span")
        timing.className = "text-muted"
        timing.textContent = `${cue.start.toFixed(3)}–${cue.end.toFixed(3)}s`
        row.append(timing)
        const text = document.createElement("p")
        text.className = "broadcast-transcript"
        for (const segment of cue.segments || [{ text: cue.text, match: false }]) {
          if (segment.match) {
            const mark = document.createElement("mark")
            mark.className = "broadcast-match"
            mark.textContent = segment.text
            text.append(mark)
          } else {
            text.append(document.createTextNode(segment.text))
          }
        }
        row.append(text)
        for (const [label, action, offset] of [["Play", "seek", cue.start], ["Set clip in", "selectStart", cue.start], ["Set clip out", "selectEnd", cue.end]]) {
          const control = document.createElement("button")
          control.type = "button"
          control.className = "btn btn-sm"
          control.textContent = label
          control.dataset.action = `broadcast-player#${action}`
          control.dataset.offset = offset
          row.append(control)
        }
        results.append(row)
      }
    } catch {
      results.textContent = "Subtitle files could not load. Please try again."
      button.disabled = false
    }
  }

  selectStart(event) { this.setBound("start", Number(event.currentTarget.dataset.offset)) }
  selectEnd(event) { this.setBound("end", Number(event.currentTarget.dataset.offset)) }
  selectSegment(event) {
    this.writeBounds(Number(event.currentTarget.dataset.start), Number(event.currentTarget.dataset.end))
    this.selectionChanged()
  }

  timecodeChanged(event) {
    const bound = event.currentTarget.dataset.bound
    const value = parseTimecode(event.currentTarget.value)
    event.currentTarget.setCustomValidity(value === null ? "Use HH:MM:SS.mmm." : "")
    if (value === null) {
      this.showValidationError("Enter a valid timecode as HH:MM:SS.mmm, MM:SS.mmm, or seconds.")
      return
    }
    if (bound === "start" || bound === "end") this.setBound(bound, value)
  }

  selectionChanged(options = {}) {
    const from = Number(this.startTarget.value), to = Number(this.endTarget.value)
    const error = validateRange(from, to, { availableEnd: this.availableEndValue, gaps: this.gapsValue })
    if (this.hasStartTimecodeTarget && document.activeElement !== this.startTimecodeTarget) this.startTimecodeTarget.value = formatTimecode(from)
    if (this.hasEndTimecodeTarget && document.activeElement !== this.endTimecodeTarget) this.endTimecodeTarget.value = formatTimecode(to)
    if (this.hasSelectionTarget) {
      this.selectionTarget.textContent = error || `Clip selected: ${formatTimecode(from)}–${formatTimecode(to)} (${formatTimecode(to - from)}).`
      this.selectionTarget.dataset.valid = String(!error)
    }
    if (this.hasDurationTarget) this.durationTarget.textContent = formatTimecode(Math.max(0, to - from))
    this.submitTargets.forEach(control => { control.disabled = Boolean(error); control.setAttribute("aria-disabled", String(Boolean(error))) })
    this.exportFormSubmitters().forEach(control => { control.disabled = Boolean(error) })
    this.renderTimeline()
    if (options.persist !== false) this.saveDraft()
    if (options.updateUrl === false) return !error
    const url = new URL(window.location.href)
    url.searchParams.set("clip_start", this.startTarget.value)
    url.searchParams.set("clip_end", this.endTarget.value)
    window.history.replaceState({}, "", url)
    this.element.querySelectorAll("nav a").forEach(link => {
      const target = withSelectionParams(link.getAttribute("href"), window.location.href, this.startTarget.value, this.endTarget.value)
      if (target) link.href = target
    })
    return !error
  }

  preserveSelection(event) {
    for (const [name, value] of [["clip_start", this.startTarget.value], ["clip_end", this.endTarget.value]]) {
      let input = event.currentTarget.querySelector(`input[name="${name}"]`)
      if (!input) { input = document.createElement("input"); input.type = "hidden"; input.name = name; event.currentTarget.append(input) }
      input.value = value
    }
    this.saveDraft()
  }

  validateExport(event) {
    const visibleBounds = [
      [this.hasStartTimecodeTarget ? this.startTimecodeTarget : null, "start"],
      [this.hasEndTimecodeTarget ? this.endTimecodeTarget : null, "end"]
    ]
    let timecodesValid = true
    for (const [input, bound] of visibleBounds) {
      if (!input) continue
      const parsed = parseTimecode(input.value)
      input.setCustomValidity(parsed === null ? "Use HH:MM:SS.mmm, MM:SS.mmm, or seconds." : "")
      if (parsed === null) timecodesValid = false
      if (parsed !== null) this[`${bound}Target`].value = parsed.toFixed(3)
    }
    const valid = timecodesValid && this.selectionChanged()
    if (!timecodesValid) this.showValidationError("Enter valid in and out timecodes before exporting.")
    const formValid = event.currentTarget.checkValidity()
    if (valid && formValid) return
    event.preventDefault()
    if (!formValid) event.currentTarget.reportValidity()
    else if (this.hasSelectionTarget) this.selectionTarget.focus?.()
  }

  seek(event) {
    const offset = Number(event.currentTarget.dataset.offset)
    const position = offset - this.originValue
    if (this.hasVideoTarget && position >= 0 && offset <= this.windowEndValue) {
      this.videoTarget.currentTime = position
      this.videoTarget.play().catch(() => {})
    } else {
      const url = new URL(window.location.href)
      url.searchParams.set("at", offset)
      url.searchParams.set("clip_start", this.startTarget.value)
      url.searchParams.set("clip_end", this.endTarget.value)
      window.location.assign(url)
    }
  }

  previewSelection() {
    const start = Number(this.startTarget.value), end = Number(this.endTarget.value)
    if (!this.selectionChanged()) return
    if (start < this.originValue || end > this.windowEndValue || !this.hasVideoTarget) {
      this.navigateTo(start, { preview: true })
      return
    }
    this.startRangePreview()
  }

  toggleLoop() {
    if (this.rangePreviewActive && this.hasVideoTarget && this.videoTarget.paused) this.videoTarget.play().catch(() => {})
  }

  zoomSelection() {
    const start = Number(this.startTarget.value), end = Number(this.endTarget.value)
    if (!validateRange(start, end, { availableEnd: this.availableEndValue, gaps: this.gapsValue })) {
      const padding = Math.min(Math.max((end - start) * 0.05, 0.5), 10)
      this.viewportStart = clamp(start - padding, 0, this.availableEndValue)
      this.viewportEnd = clamp(end + padding, this.viewportStart + 0.001, this.availableEndValue)
      this.renderTimeline()
    }
  }

  zoomNarrowInitialSelection() {
    const start = Number(this.startTarget.value), end = Number(this.endTarget.value)
    const viewportDuration = this.viewportEnd - this.viewportStart
    const valid = !validateRange(start, end, { availableEnd: this.availableEndValue, gaps: this.gapsValue })
    const outsideViewport = start < this.viewportStart || end > this.viewportEnd
    if (valid && (outsideViewport || end - start < viewportDuration * 0.1)) this.zoomSelection()
  }

  resetZoom() {
    this.viewportStart = this.originValue
    this.viewportEnd = this.windowEndValue > this.originValue ? this.windowEndValue : this.availableEndValue
    this.renderTimeline()
  }

  timelinePointerDown(event) {
    if (event.button !== undefined && event.button !== 0) return
    const roleElement = event.target.closest("[data-role]")
    const role = roleElement?.dataset.role || event.currentTarget.dataset.role || "seek"
    const timeline = this.hasTimelineTarget ? this.timelineTarget : event.currentTarget
    if (!timeline.getBoundingClientRect) return
    event.preventDefault()
    const initialStart = Number(this.startTarget.value), initialEnd = Number(this.endTarget.value)
    const anchor = this.timelineValue(event.clientX, timeline)
    const move = moveEvent => {
      const value = this.timelineValue(moveEvent.clientX, timeline)
      if (role === "start") this.setBound("start", Math.min(value, Number(this.endTarget.value) - 0.001))
      else if (role === "end") this.setBound("end", Math.max(value, Number(this.startTarget.value) + 0.001))
      else if (role === "selection") {
        const duration = initialEnd - initialStart
        const delta = value - anchor
        const start = clamp(initialStart + delta, 0, Math.max(0, this.availableEndValue - duration))
        this.writeBounds(start, start + duration)
        this.selectionChanged()
      } else this.seekToRecordingTime(value)
    }
    const finish = () => {
      window.removeEventListener("pointermove", move)
      window.removeEventListener("pointerup", finish)
      window.removeEventListener("pointercancel", finish)
    }
    const signal = this.listenerController.signal
    window.addEventListener("pointermove", move, { signal })
    window.addEventListener("pointerup", finish, { once: true, signal })
    window.addEventListener("pointercancel", finish, { once: true, signal })
    move(event)
  }

  handleKeydown(event) {
    const bound = event.currentTarget.dataset.bound
    if (bound !== "start" && bound !== "end") return
    let value
    if (event.key === "Home") value = 0
    else if (event.key === "End") value = this.availableEndValue
    else {
      const direction = event.key === "ArrowLeft" || event.key === "ArrowDown" ? -1 : event.key === "ArrowRight" || event.key === "ArrowUp" ? 1 : 0
      const page = event.key === "PageDown" ? -5 : event.key === "PageUp" ? 5 : 0
      if (!direction && !page) return
      value = Number(this[`${bound}Target`].value) + (page || direction * (event.shiftKey ? 1 : 0.1))
    }
    event.preventDefault()
    event.stopPropagation()
    const minimum = bound === "end" ? Number(this.startTarget.value) + 0.001 : 0
    const maximum = bound === "start" ? Number(this.endTarget.value) - 0.001 : this.availableEndValue
    this.setBound(bound, clamp(value, minimum, maximum))
  }

  persistentFieldChanged() { this.saveDraft() }

  keyboardShortcut(event) {
    if (event.defaultPrevented || event.ctrlKey || event.metaKey || event.altKey || this.isEditable(event.target)) return
    if (event.code === "Space") { event.preventDefault(); this.playPause(); return }
    if (event.key.toLowerCase() === "i") { event.preventDefault(); this.markStart(); return }
    if (event.key.toLowerCase() === "o") { event.preventDefault(); this.markEnd(); return }
    if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
      event.preventDefault()
      this.seekBy((event.key === "ArrowLeft" ? -1 : 1) * (event.shiftKey ? 0.1 : 5))
    }
  }

  get recordingTime() { return this.originValue + (this.hasVideoTarget ? this.videoTarget.currentTime : 0) }

  setBound(bound, value) {
    if (!Number.isFinite(value) || !this.hasStartTarget || !this.hasEndTarget) return
    this[`${bound}Target`].value = value.toFixed(3)
    this.selectionChanged()
  }

  writeBounds(start, end) {
    this.startTarget.value = Number(start).toFixed(3)
    this.endTarget.value = Number(end).toFixed(3)
  }

  seekBy(seconds) {
    if (!this.hasVideoTarget) return
    this.videoTarget.currentTime = clamp(this.videoTarget.currentTime + seconds, 0, Number.isFinite(this.videoTarget.duration) ? this.videoTarget.duration : this.videoTarget.currentTime + seconds)
  }

  seekToRecordingTime(value) {
    if (value < this.originValue || value > this.windowEndValue) return
    if (this.hasVideoTarget) this.videoTarget.currentTime = value - this.originValue
  }

  timelineValue(clientX, timeline) {
    const bounds = timeline.getBoundingClientRect()
    const ratio = bounds.width ? clamp((clientX - bounds.left) / bounds.width, 0, 1) : 0
    return this.viewportStart + ratio * (this.viewportEnd - this.viewportStart)
  }

  renderTimeline() {
    if (!this.hasTimelineTarget || !this.hasStartTarget || !this.hasEndTarget) return
    const start = Number(this.startTarget.value), end = Number(this.endTarget.value)
    const startPercent = timelinePercent(start, this.viewportStart, this.viewportEnd)
    const endPercent = timelinePercent(end, this.viewportStart, this.viewportEnd)
    const playheadPercent = timelinePercent(this.recordingTime, this.viewportStart, this.viewportEnd)
    this.timelineTarget.style.setProperty("--clip-start", `${startPercent}%`)
    this.timelineTarget.style.setProperty("--clip-end", `${endPercent}%`)
    this.timelineTarget.style.setProperty("--playhead", `${playheadPercent}%`)
    if (this.hasSelectionRangeTarget) {
      this.selectionRangeTarget.style.left = `${startPercent}%`
      this.selectionRangeTarget.style.width = `${Math.max(0, endPercent - startPercent)}%`
    }
    if (this.hasPlayheadTarget) this.playheadTarget.style.left = `${playheadPercent}%`
    this.renderGaps()
    for (const bound of ["start", "end"]) {
      const percent = bound === "start" ? startPercent : endPercent
      this.timelineTarget.querySelectorAll(`[data-role="${bound}"]`).forEach(handle => {
        handle.style.left = `${percent}%`
        handle.setAttribute("aria-valuemin", "0")
        handle.setAttribute("aria-valuemax", String(this.availableEndValue))
        handle.setAttribute("aria-valuenow", String(bound === "start" ? start : end))
        handle.setAttribute("aria-valuetext", formatTimecode(bound === "start" ? start : end))
      })
    }
    if (this.hasViewportLabelTarget) this.viewportLabelTarget.textContent = `${formatTimecode(this.viewportStart)}–${formatTimecode(this.viewportEnd)}`
  }

  renderGaps() {
    const signature = JSON.stringify([this.viewportStart, this.viewportEnd, this.gapsValue])
    if (signature === this.renderedGapsSignature) return
    this.renderedGapsSignature = signature
    this.timelineTarget.querySelectorAll(".broadcast-timeline-gap").forEach(element => element.remove())
    for (const gap of this.gapsValue) {
      if (!Array.isArray(gap) || gap.length < 2 || Number(gap[1]) <= this.viewportStart || Number(gap[0]) >= this.viewportEnd) continue
      const left = timelinePercent(Number(gap[0]), this.viewportStart, this.viewportEnd)
      const right = timelinePercent(Number(gap[1]), this.viewportStart, this.viewportEnd)
      const element = document.createElement("div")
      element.className = "broadcast-timeline-gap"
      element.style.left = `${left}%`
      element.style.width = `${Math.max(0, right - left)}%`
      element.setAttribute("aria-hidden", "true")
      const grid = this.timelineTarget.querySelector(".broadcast-timeline-grid")
      grid?.after(element)
    }
  }

  timeUpdated() {
    if (this.rangePreviewActive && this.recordingTime >= Number(this.endTarget.value) - 0.02) {
      if (this.hasLoopTarget && this.loopTarget.checked) {
        this.videoTarget.currentTime = Number(this.startTarget.value) - this.originValue
        this.videoTarget.play().catch(() => {})
      } else {
        this.finishRangePreview()
      }
    }
    this.updatePlaybackDisplay()
  }

  updatePlaybackDisplay() {
    if (this.hasCurrentTimeTarget) this.currentTimeTarget.textContent = formatTimecode(this.recordingTime)
    if (this.hasDurationTarget) this.durationTarget.textContent = formatTimecode(Math.max(0, Number(this.endTarget.value) - Number(this.startTarget.value)))
    this.renderTimeline()
  }

  updatePlayButton() {
    if (!this.hasPlayButtonTarget) return
    this.playButtonTarget.textContent = this.videoTarget.paused ? "Play" : "Pause"
    this.playButtonTarget.setAttribute("aria-label", this.videoTarget.paused ? "Play video" : "Pause video")
  }

  updateRate() {
    this.rateValue = this.videoTarget.playbackRate
    if (this.hasRateTarget) this.rateTarget.value = String(this.videoTarget.playbackRate)
  }

  startRangePreview() {
    if (!this.hasVideoTarget) return
    this.cancelPreviewFrameMonitor()
    this.rangePreviewActive = true
    this.previewNeedsGesture = false
    this.videoTarget.currentTime = Number(this.startTarget.value) - this.originValue
    const playback = this.videoTarget.play()
    playback?.catch(() => {
      this.rangePreviewActive = false
      this.cancelPreviewFrameMonitor()
      this.previewNeedsGesture = true
      this.updatePreviewButton()
    })
    this.monitorPreviewFrames()
    this.updatePreviewButton()
  }

  monitorPreviewFrames() {
    if (!this.rangePreviewActive || typeof this.videoTarget.requestVideoFrameCallback !== "function") return
    this.previewFrameCallback = this.videoTarget.requestVideoFrameCallback((_now, metadata) => {
      this.previewFrameCallback = null
      if (!this.rangePreviewActive) return
      const mediaTime = Number.isFinite(metadata.mediaTime) ? metadata.mediaTime : this.videoTarget.currentTime
      const out = Number(this.endTarget.value) - this.originValue
      if (mediaTime >= out - 0.001) {
        if (this.hasLoopTarget && this.loopTarget.checked) {
          this.videoTarget.currentTime = Number(this.startTarget.value) - this.originValue
          this.monitorPreviewFrames()
        } else this.finishRangePreview()
      } else this.monitorPreviewFrames()
    })
  }

  finishRangePreview() {
    this.rangePreviewActive = false
    this.cancelPreviewFrameMonitor()
    this.videoTarget.pause()
    const out = Number(this.endTarget.value) - this.originValue
    const maximum = Number.isFinite(this.videoTarget.duration) ? this.videoTarget.duration : out
    this.videoTarget.currentTime = clamp(out, 0, maximum)
    this.updatePlaybackDisplay()
    this.updatePreviewButton()
  }

  cancelPreviewFrameMonitor() {
    if (this.previewFrameCallback != null && this.hasVideoTarget && typeof this.videoTarget.cancelVideoFrameCallback === "function") {
      this.videoTarget.cancelVideoFrameCallback(this.previewFrameCallback)
    }
    this.previewFrameCallback = null
  }

  updatePreviewButton() {
    if (!this.hasPreviewButtonTarget) return
    this.previewButtonTarget.textContent = this.rangePreviewActive ? "Previewing selection…" : this.previewNeedsGesture ? "Play selection" : "Preview selection"
  }

  navigateTo(offset, { preview = false } = {}) {
    const url = new URL(window.location.href)
    url.searchParams.set("at", offset.toFixed(3))
    url.searchParams.set("clip_start", this.startTarget.value)
    url.searchParams.set("clip_end", this.endTarget.value)
    if (preview) url.searchParams.set("preview_selection", "1")
    window.location.assign(url)
  }

  clearPreviewQuery() {
    const url = new URL(window.location.href)
    url.searchParams.delete("preview_selection")
    window.history.replaceState({}, "", url)
  }

  isEditable(element) {
    return element?.matches?.("input, textarea, select, button, a, [contenteditable], [role=textbox], [role=button], [role=slider]") || element?.isContentEditable
  }

  showValidationError(message) {
    if (this.hasSelectionTarget) {
      this.selectionTarget.textContent = message
      this.selectionTarget.dataset.valid = "false"
    }
    this.submitTargets.forEach(control => { control.disabled = true; control.setAttribute("aria-disabled", "true") })
    this.exportFormSubmitters().forEach(control => { control.disabled = true })
  }

  exportFormSubmitters() {
    const form = this.hasStartTarget ? this.startTarget.closest("form") : null
    return form ? Array.from(form.querySelectorAll('button[type="submit"], input[type="submit"]')) : []
  }

  get storageKey() { return `broadcast-player:${this.recordingIdValue}` }

  restoreDraft() {
    if (!this.hasRecordingIdValue) return
    let draft
    try { draft = JSON.parse(sessionStorage.getItem(this.storageKey) || "null") } catch { return }
    if (!draft || typeof draft !== "object") return
    const query = new URL(window.location.href).searchParams
    if (!query.has("clip_start") && !query.has("clip_end") && Number.isFinite(draft.start) && Number.isFinite(draft.end)) {
      this.writeBounds(draft.start, draft.end)
    }
    this.persistentElements().forEach(element => this.restorePersistentElement(element, draft.fields || {}))
  }

  saveDraft() {
    if (!this.hasRecordingIdValue || !this.hasStartTarget || !this.hasEndTarget) return
    const fields = {}
    this.persistentElements().forEach(element => {
      const key = this.persistentKey(element)
      if (!key) return
      if (element.type === "checkbox") {
        fields[key] ||= []
        if (element.checked) fields[key].push(element.value)
      } else if (element.type === "radio") {
        if (element.checked) fields[key] = element.value
      } else fields[key] = element.value
    })
    try {
      sessionStorage.setItem(this.storageKey, JSON.stringify({ start: Number(this.startTarget.value), end: Number(this.endTarget.value), fields }))
    } catch { /* Private browsing or storage limits must not break clipping. */ }
  }

  persistentElements() {
    const elements = Array.from(this.element.querySelectorAll("[data-persist-key]"))
    for (const target of [...this.titleTargets, ...this.exportModeTargets, ...this.subtitleChoiceTargets]) if (!elements.includes(target)) elements.push(target)
    return elements
  }

  persistentKey(element) {
    if (element.dataset.persistKey) return element.dataset.persistKey
    if (this.titleTargets.includes(element)) return "title"
    if (this.exportModeTargets.includes(element)) return "exportMode"
    if (this.subtitleChoiceTargets.includes(element)) return "subtitleChoice"
  }

  restorePersistentElement(element, fields) {
    const key = this.persistentKey(element)
    if (!key || fields[key] === undefined) return
    if (element.type === "checkbox") element.checked = Array.isArray(fields[key]) && fields[key].includes(element.value)
    else if (element.type === "radio") element.checked = fields[key] === element.value
    else element.value = fields[key]
  }

  installPersistentFieldListeners() {
    this.persistentElements().forEach(element => {
      element.addEventListener(element.matches("input[type=text], textarea") ? "input" : "change", () => this.saveDraft(), { signal: this.listenerController.signal })
    })
  }

  installTimecodeListeners() {
    for (const input of [...this.startTimecodeTargets, ...this.endTimecodeTargets]) {
      input.addEventListener("input", event => this.timecodeChanged(event), { signal: this.listenerController.signal })
    }
  }
}
