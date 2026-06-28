import { Controller } from "@hotwired/stimulus"

const DEFAULT_FILTER = "all"
const FILTERS = new Set([DEFAULT_FILTER, "codex", "opencode"])

export default class extends Controller {
  static targets = ["button", "empty", "group", "item", "project"]
  static values = { storageKey: String }

  connect() {
    this.currentFilter = this.normalize(this.read() || DEFAULT_FILTER)
    this.apply()
  }

  select(event) {
    this.currentFilter = this.normalize(event.currentTarget.dataset.sessionFilterRuntimeValue)
    this.write(this.currentFilter)
    this.apply()
  }

  apply() {
    this.itemTargets.forEach((item) => {
      item.hidden = !this.itemMatches(item)
    })

    this.groupTargets.forEach((group) => {
      group.hidden = !this.hasVisibleItem(group)
    })

    this.projectTargets.forEach((project) => {
      project.hidden = !this.hasVisibleItem(project)
    })

    this.updateButtons()
    this.updateEmptyState()
  }

  itemMatches(item) {
    return this.currentFilter === DEFAULT_FILTER || item.dataset.runtimeName === this.currentFilter
  }

  hasVisibleItem(container) {
    return this.itemTargets.some((item) => container.contains(item) && !item.hidden)
  }

  updateButtons() {
    this.buttonTargets.forEach((button) => {
      const active = this.normalize(button.dataset.sessionFilterRuntimeValue) === this.currentFilter
      button.classList.toggle("ap-quiet-link-active", active)
      button.setAttribute("aria-pressed", active ? "true" : "false")
    })
  }

  updateEmptyState() {
    if (!this.hasEmptyTarget) return

    this.emptyTarget.hidden = this.projectTargets.some((project) => !project.hidden)
  }

  normalize(value) {
    const filter = String(value || DEFAULT_FILTER)
    return FILTERS.has(filter) ? filter : DEFAULT_FILTER
  }

  read() {
    try {
      return localStorage.getItem(this.storageKey)
    } catch {
      return null
    }
  }

  write(value) {
    try {
      localStorage.setItem(this.storageKey, value)
    } catch {
      // Storage can be unavailable in private browsing; filtering still works.
    }
  }

  get storageKey() {
    return this.hasStorageKeyValue ? this.storageKeyValue : "agent-control-room:session-runtime-filter"
  }
}
