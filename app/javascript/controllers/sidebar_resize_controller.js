import { Controller } from "@hotwired/stimulus"

const DEFAULT_MIN_WIDTH = 176
const DEFAULT_MAX_WIDTH = 420
const DEFAULT_STORAGE_KEY = "agent-control-room:session-sidebar-width"
const DEFAULT_RESERVED_WIDTH = 360
const DEFAULT_KEYBOARD_STEP = 16

export default class extends Controller {
  static targets = ["sidebar", "handle"]
  static values = {
    max: Number,
    min: Number,
    reservedWidth: Number,
    storageKey: String
  }

  connect() {
    this.dragging = false
    this.drag = this.drag.bind(this)
    this.stop = this.stop.bind(this)
    this.syncToViewport = this.syncToViewport.bind(this)

    this.restoreWidth()
    this.updateHandle()
    this.element.dataset.sidebarResizeReady = "true"
    window.addEventListener("resize", this.syncToViewport)
  }

  disconnect() {
    window.removeEventListener("resize", this.syncToViewport)
    delete this.element.dataset.sidebarResizeReady
    this.stop()
  }

  start(event) {
    if (event.button !== undefined && event.button !== 0) return
    if (this.isStackedLayout) return

    event.preventDefault()

    this.dragging = true
    this.startX = event.clientX
    this.startWidth = this.currentWidth
    this.handleTarget.classList.add("ap-sidebar-resizer-active")
    document.documentElement.classList.add("ap-sidebar-resizing")

    window.addEventListener("pointermove", this.drag)
    window.addEventListener("pointerup", this.stop, { once: true })
    window.addEventListener("pointercancel", this.stop, { once: true })

    try {
      this.handleTarget.setPointerCapture(event.pointerId)
    } catch {
      // Pointer capture can fail if the browser has already released the pointer.
    }
  }

  drag(event) {
    if (!this.dragging) return

    event.preventDefault()
    this.setWidth(this.startWidth + event.clientX - this.startX)
  }

  stop() {
    if (!this.dragging) return

    this.dragging = false
    this.handleTarget.classList.remove("ap-sidebar-resizer-active")
    document.documentElement.classList.remove("ap-sidebar-resizing")
    window.removeEventListener("pointermove", this.drag)
    window.removeEventListener("pointerup", this.stop)
    window.removeEventListener("pointercancel", this.stop)
    this.persistWidth()
  }

  handleKeydown(event) {
    if (this.isStackedLayout) return

    const step = event.shiftKey ? DEFAULT_KEYBOARD_STEP * 2 : DEFAULT_KEYBOARD_STEP
    let nextWidth

    if (event.key === "ArrowLeft") {
      nextWidth = this.currentWidth - step
    } else if (event.key === "ArrowRight") {
      nextWidth = this.currentWidth + step
    } else if (event.key === "Home") {
      nextWidth = this.minWidth
    } else if (event.key === "End") {
      nextWidth = this.maxAvailableWidth
    } else {
      return
    }

    event.preventDefault()
    this.setWidth(nextWidth)
    this.persistWidth()
  }

  syncToViewport() {
    if (this.isStackedLayout) return

    this.setWidth(this.currentWidth)
  }

  restoreWidth() {
    const storedWidth = this.readStoredWidth()
    if (storedWidth) this.setWidth(storedWidth)
  }

  setWidth(width) {
    const nextWidth = this.clampWidth(width)

    this.width = nextWidth
    this.element.style.setProperty("--ap-session-sidebar-width", `${nextWidth}px`)
    this.updateHandle(nextWidth)
  }

  persistWidth() {
    try {
      localStorage.setItem(this.storageKey, String(Math.round(this.width || this.currentWidth)))
    } catch {
      // Storage can be unavailable in private browsing; resizing still works.
    }
  }

  readStoredWidth() {
    try {
      const value = Number.parseInt(localStorage.getItem(this.storageKey), 10)
      return Number.isFinite(value) ? value : null
    } catch {
      return null
    }
  }

  updateHandle(width = this.currentWidth) {
    if (!this.hasHandleTarget) return

    this.handleTarget.setAttribute("aria-valuemin", String(this.minWidth))
    this.handleTarget.setAttribute("aria-valuemax", String(this.maxAvailableWidth))
    this.handleTarget.setAttribute("aria-valuenow", String(Math.round(width)))
  }

  clampWidth(width) {
    return Math.round(Math.min(Math.max(width, this.minWidth), this.maxAvailableWidth))
  }

  get currentWidth() {
    return this.width || this.sidebarTarget.getBoundingClientRect().width || DEFAULT_MIN_WIDTH
  }

  get minWidth() {
    return this.hasMinValue ? this.minValue : DEFAULT_MIN_WIDTH
  }

  get maxWidth() {
    return this.hasMaxValue ? this.maxValue : DEFAULT_MAX_WIDTH
  }

  get maxAvailableWidth() {
    const reservedWidth = this.hasReservedWidthValue ? this.reservedWidthValue : DEFAULT_RESERVED_WIDTH
    const availableWidth = this.element.getBoundingClientRect().width - reservedWidth

    return Math.max(this.minWidth, Math.min(this.maxWidth, availableWidth || this.maxWidth))
  }

  get storageKey() {
    return this.hasStorageKeyValue ? this.storageKeyValue : DEFAULT_STORAGE_KEY
  }

  get isStackedLayout() {
    return window.matchMedia("(max-width: 1180px)").matches
  }
}
