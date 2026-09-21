import assert from "node:assert/strict"
import { afterEach, test } from "node:test"
import { JSDOM } from "jsdom"

let application
let dom

function editorMarkup({ start = "110.000", end = "200.000" } = {}) {
  return `
    <main data-controller="broadcast-player"
          data-broadcast-player-source-value="/playlist.m3u8"
          data-broadcast-player-origin-value="100"
          data-broadcast-player-seek-value="0"
          data-broadcast-player-recording-id-value="recording-1"
          data-broadcast-player-available-end-value="300"
          data-broadcast-player-window-end-value="250"
          data-broadcast-player-gaps-value="[]">
      <video data-broadcast-player-target="video"></video>
      <nav><a href="?page=2">Results</a></nav>
      <form id="export" data-action="submit->broadcast-player#validateExport">
        <input type="hidden" name="media_clip[start_offset]" value="${start}" data-broadcast-player-target="start">
        <input type="hidden" name="media_clip[end_offset]" value="${end}" data-broadcast-player-target="end">
        <input value="00:01:50.000" data-bound="start" data-broadcast-player-target="startTimecode">
        <input value="00:03:20.000" data-bound="end" data-broadcast-player-target="endTimecode">
        <input value="Original title" data-persist-key="title" data-broadcast-player-target="title">
        <select data-persist-key="exportMode" data-broadcast-player-target="exportMode">
          <option value="exact">Exact</option><option value="copy">Copy</option>
        </select>
        <label><input type="checkbox" value="en" data-persist-key="subtitleChoice" data-broadcast-player-target="subtitleChoice"> English</label>
        <label><input type="checkbox" value="fr" data-persist-key="subtitleChoice" data-broadcast-player-target="subtitleChoice"> French</label>
        <strong data-broadcast-player-target="duration"></strong>
        <p tabindex="-1" data-broadcast-player-target="selection"></p>
        <button type="button" data-action="broadcast-player#previewSelection" data-broadcast-player-target="previewButton">Preview selection</button>
        <button type="submit" data-broadcast-player-target="submit">Export</button>
      </form>
      <div data-broadcast-player-target="timeline" data-role="seek" data-action="pointerdown->broadcast-player#timelinePointerDown">
        <div class="broadcast-timeline-grid"></div>
        <div data-role="selection" data-broadcast-player-target="selectionRange"></div>
        <div data-broadcast-player-target="playhead"></div>
        <button type="button" data-role="start"></button>
        <button type="button" data-role="end"></button>
      </div>
      <span data-broadcast-player-target="viewportLabel"></span>
    </main>`
}

async function startEditor({ url = "https://example.test/admin/broadcasts/1", markup, draft } = {}) {
  dom = new JSDOM(markup || editorMarkup(), { url, pretendToBeVisual: true })
  const globals = [
    "window", "document", "navigator", "Node", "Element", "HTMLElement", "HTMLInputElement",
    "Event", "CustomEvent", "KeyboardEvent", "MouseEvent", "MutationObserver", "AbortController",
    "AbortSignal", "sessionStorage"
  ]
  for (const name of globals) {
    Object.defineProperty(globalThis, name, { configurable: true, writable: true, value: dom.window[name] })
  }

  if (draft) sessionStorage.setItem("broadcast-player:recording-1", JSON.stringify(draft))

  const video = document.querySelector("video")
  let paused = true
  Object.defineProperties(video, {
    paused: { configurable: true, get: () => paused },
    duration: { configurable: true, value: 150 },
    play: { configurable: true, value: () => { paused = false; return Promise.resolve() } },
    pause: { configurable: true, value: () => { paused = true } },
    load: { configurable: true, value: () => {} },
    canPlayType: { configurable: true, value: () => "maybe" }
  })

  const [{ Application }, { default: BroadcastPlayerController }] = await Promise.all([
    import("@hotwired/stimulus"),
    import("../../app/javascript/controllers/broadcast_player_controller.js")
  ])
  application = Application.start()
  application.register("broadcast-player", BroadcastPlayerController)
  await new Promise(resolve => setTimeout(resolve, 0))
  return document.querySelector("[data-controller='broadcast-player']")
}

afterEach(() => {
  application?.stop()
  dom?.window.close()
  application = undefined
  dom = undefined
})

test("restores draft bounds and persistent fields when the URL has no selection", async () => {
  await startEditor({
    draft: {
      start: 125.25,
      end: 142.75,
      fields: { title: "Restored title", exportMode: "copy", subtitleChoice: ["fr"] }
    }
  })

  assert.equal(document.querySelector("[data-broadcast-player-target='start']").value, "125.250")
  assert.equal(document.querySelector("[data-broadcast-player-target='end']").value, "142.750")
  assert.equal(document.querySelector("[data-persist-key='title']").value, "Restored title")
  assert.equal(document.querySelector("select").value, "copy")
  assert.equal(document.querySelector("input[value='en']").checked, false)
  assert.equal(document.querySelector("input[value='fr']").checked, true)
  assert.equal(new URL(window.location.href).searchParams.get("clip_start"), "125.250")
})

test("URL selection takes precedence over draft bounds while persistent fields still restore", async () => {
  await startEditor({
    url: "https://example.test/admin/broadcasts/1?clip_start=130.000&clip_end=160.000",
    markup: editorMarkup({ start: "130.000", end: "160.000" }),
    draft: { start: 10, end: 20, fields: { title: "Draft title" } }
  })

  assert.equal(document.querySelector("[data-broadcast-player-target='start']").value, "130.000")
  assert.equal(document.querySelector("[data-broadcast-player-target='end']").value, "160.000")
  assert.equal(document.querySelector("[data-persist-key='title']").value, "Draft title")
})

test("validates edited timecodes and submits their exact hidden boundaries", async () => {
  await startEditor()
  const form = document.querySelector("#export")
  const startTimecode = document.querySelector("[data-bound='start']")
  const endTimecode = document.querySelector("[data-bound='end']")
  const status = document.querySelector("[data-broadcast-player-target='selection']")
  const submit = form.querySelector("button[type='submit']")

  startTimecode.value = "not a timecode"
  const malformedSubmitted = form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
  assert.equal(malformedSubmitted, false)
  assert.match(startTimecode.validationMessage, /HH:MM:SS/)
  assert.match(status.textContent, /valid in and out timecodes/)

  startTimecode.value = "00:03:30.000"
  startTimecode.dispatchEvent(new Event("input", { bubbles: true }))
  assert.equal(status.dataset.valid, "false")
  assert.match(status.textContent, /after the in point/)
  assert.equal(submit.disabled, true)

  startTimecode.value = "02:05.125"
  startTimecode.dispatchEvent(new Event("input", { bubbles: true }))
  endTimecode.value = "02:20.875"
  endTimecode.dispatchEvent(new Event("input", { bubbles: true }))
  const submitted = form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))

  assert.equal(submitted, true)
  assert.equal(form.elements.namedItem("media_clip[start_offset]").value, "125.125")
  assert.equal(form.elements.namedItem("media_clip[end_offset]").value, "140.875")
  assert.equal(status.dataset.valid, "true")
  assert.equal(submit.disabled, false)
})

test("dragging the timeline end handle updates selection, styles, and URL", async () => {
  await startEditor()
  const timeline = document.querySelector("[data-broadcast-player-target='timeline']")
  const endHandle = timeline.querySelector("[data-role='end']")
  timeline.getBoundingClientRect = () => ({ left: 20, width: 200 })

  endHandle.dispatchEvent(new MouseEvent("pointerdown", { bubbles: true, cancelable: true, button: 0, clientX: 120 }))
  window.dispatchEvent(new MouseEvent("pointermove", { clientX: 140 }))
  window.dispatchEvent(new MouseEvent("pointerup"))
  window.dispatchEvent(new MouseEvent("pointermove", { clientX: 160 }))

  assert.equal(document.querySelector("[data-broadcast-player-target='end']").value, "190.000")
  assert.equal(endHandle.getAttribute("aria-valuenow"), "190")
  assert.ok(Math.abs(parseFloat(document.querySelector("[data-broadcast-player-target='selectionRange']").style.width) - 53.3333) < 0.001)
  assert.equal(new URL(window.location.href).searchParams.get("clip_end"), "190.000")
})

test("previews the selected range and stops playback at the out point", async () => {
  await startEditor()
  const video = document.querySelector("video")
  const preview = document.querySelector("[data-broadcast-player-target='previewButton']")

  preview.click()
  assert.equal(video.currentTime, 10)
  assert.equal(video.paused, false)
  assert.equal(preview.textContent, "Previewing selection…")

  video.currentTime = 100.3
  video.dispatchEvent(new Event("timeupdate"))
  assert.equal(video.paused, true)
  assert.equal(video.currentTime, 100)
  assert.equal(preview.textContent, "Preview selection")
})
