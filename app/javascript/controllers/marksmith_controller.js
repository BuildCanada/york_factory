import { MarksmithController } from "@avo-hq/marksmith"

// Marksmith's stock controller uploads files with ActiveStorage DirectUpload,
// which PUTs straight from the browser to the storage service (R2) and needs
// bucket CORS, and it inserts relative /rails/active_storage/... URLs that
// break when CMS content is rendered on other hosts (buildcanada.com).
//
// This subclass keeps the editor but routes paste / drag & drop / button
// uploads through POST /admin/uploads (same-origin, server-side ActiveStorage
// upload) and inserts the absolute blob URL the endpoint returns.
export default class extends MarksmithController {
  dropUpload(event) {
    if (!this.fileUploadsEnabledValue) return

    event.preventDefault()
    this.uploadFiles(event.dataTransfer.files)
  }

  pasteUpload(event) {
    if (!this.fileUploadsEnabledValue) return
    if (!event.clipboardData.files.length) return

    event.preventDefault()
    this.uploadFiles(event.clipboardData.files)
  }

  buttonUpload(event) {
    event.preventDefault()

    const fileInput = document.createElement("input")
    fileInput.type = "file"
    fileInput.multiple = true
    fileInput.accept = "image/*,.pdf,.doc,.docx,.txt"
    fileInput.addEventListener("change", (e) => this.uploadFiles(e.target.files))
    fileInput.click()
  }

  uploadFiles(files) {
    Array.from(files).forEach((file) => this.uploadFile(file))
  }

  async uploadFile(file) {
    const placeholder = `![Uploading ${file.name}…]()`
    this.insertAtCursor(`${placeholder}\n`)

    try {
      const formData = new FormData()
      formData.append("file", file)

      const response = await fetch(this.attachUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
          "Accept": "application/json",
        },
        body: formData,
      })
      if (!response.ok) throw new Error(`upload returned ${response.status}`)

      const blob = await response.json()
      const prefix = blob.content_type?.startsWith("image/") ? "!" : ""
      this.replaceInField(placeholder, `${prefix}[${blob.filename}](${blob.url})`)
    } catch (error) {
      this.replaceInField(`${placeholder}\n`, "")
      console.error("[marksmith] file upload failed:", error)
      alert(`Upload of ${file.name} failed. Please try again.`)
    }
  }

  insertAtCursor(text) {
    const field = this.fieldElementTarget
    field.setRangeText(text, field.selectionStart, field.selectionEnd, "end")
  }

  replaceInField(search, replacement) {
    const field = this.fieldElementTarget
    const start = field.value.indexOf(search)
    if (start === -1) return

    field.setRangeText(replacement, start, start + search.length, "preserve")
  }
}
