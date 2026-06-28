import { Controller } from "@hotwired/stimulus"

// Persists a project's open/closed sidebar state across visits.
export default class extends Controller {
  static values = { key: String, forceOpen: Boolean }

  connect() {
    if (this.forceOpenValue) {
      this.element.open = true
      return
    }

    const stored = this.read()
    if (stored !== null) this.element.open = stored
  }

  save() {
    try {
      localStorage.setItem(this.storageKey, this.element.open ? "open" : "closed")
    } catch {
      // Storage can be unavailable in private browsing; native details still works.
    }
  }

  read() {
    try {
      const value = localStorage.getItem(this.storageKey)
      return value === null ? null : value === "open"
    } catch {
      return null
    }
  }

  get storageKey() {
    return `session-sidebar-project:${this.keyValue}`
  }
}
