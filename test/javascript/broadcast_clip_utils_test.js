import assert from "node:assert/strict"
import test from "node:test"
import { formatTimecode, parseTimecode, timelinePercent, validateRange, withSelectionParams } from "../../app/javascript/controllers/broadcast_clip_utils.js"

test("timecodes parse display forms and round to milliseconds", () => {
  assert.equal(parseTimecode("01:02:03.125"), 3723.125)
  assert.equal(parseTimecode("02:03.5"), 123.5)
  assert.equal(parseTimecode("90:00"), 5400)
  assert.equal(parseTimecode("12.25"), 12.25)
  assert.equal(parseTimecode("1:60"), null)
  assert.equal(parseTimecode("hello"), null)
  assert.equal(formatTimecode(3723.1254), "01:02:03.125")
})

test("range validation rejects invalid, unprocessed, long, and gap-spanning clips", () => {
  const options = { availableEnd: 4000, gaps: [[100, 120]] }
  assert.match(validateRange(10, 10, options), /after/)
  assert.match(validateRange(10, 1811, options), /30 minutes/)
  assert.match(validateRange(3990, 4001, options), /processed footage/)
  assert.match(validateRange(90, 110, options), /missing footage/)
  assert.equal(validateRange(120, 130, options), null)
})

test("timeline percentages clamp outside the viewport", () => {
  assert.equal(timelinePercent(150, 100, 200), 50)
  assert.equal(timelinePercent(50, 100, 200), 0)
  assert.equal(timelinePercent(250, 100, 200), 100)
})

test("selection params only update usable web links", () => {
  assert.equal(withSelectionParams(null, "https://example.test/recording", "1.000", "2.000"), null)
  assert.equal(withSelectionParams("#", "https://example.test/recording", "1.000", "2.000"), null)
  assert.equal(withSelectionParams("mailto:test@example.test", "https://example.test/recording", "1.000", "2.000"), null)
  assert.equal(
    withSelectionParams("?page=2", "https://example.test/recording?q=words", "1.000", "2.000"),
    "https://example.test/recording?page=2&clip_start=1.000&clip_end=2.000"
  )
})
