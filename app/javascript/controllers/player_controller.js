import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "playerBox", "video" ]

  connect() {
    this.detailPaneOpen = false
    this.currentVideo = -1
  }

  toggle(event) {
    const videoId = this.videoTargets.findIndex((el) => {
      const aTag = el.querySelector("a")
      return aTag == event.currentTarget
    })

    if (videoId == this.currentVideo) {
      this.closeDetailPane()
    } else {
      this.openDetailPane(videoId)
    }

    this.updateView()
  }

  close(event) {
    this.closeDetailPane()
    this.updateView()
  }

  closeDetailPane() {
    this.detailPaneOpen = false
    this.currentVideo = -1
  }

  openDetailPane(videoId) {
    this.detailPaneOpen = true
    this.currentVideo = videoId
  }

  prev(event) {
    if (this.currentVideo > 0) {
      this.currentVideo--
    }
    this.moveFocus(event.target, "prev")
    this.updateView()
  }

  next(event) {
    if (this.currentVideo < this.videoTargets.length - 1) {
      this.currentVideo++
    }
    this.moveFocus(event.target, "next")
    this.updateView()
  }

  moveFocus(target, action) {
    const buttons = document.querySelectorAll("[data-action*='player#prev'], [data-action*='player#next']")
    if (buttons.length > 0) {
      buttons[0].focus()
    }
  }

  updateView() {
    const playerBox = this.playerBoxTarget
    const videoTarget = this.videoTargets[this.currentVideo]

    if (this.detailPaneOpen && videoTarget) {
      const videoUrl = videoTarget.getAttribute("data-url")
      this.fetchPlayer(videoUrl).then(() => {
        const prevButton = document.getElementById("video-prev")
        if (prevButton) {
          prevButton.disabled = this.currentVideo === 0
          prevButton.classList.toggle("hidden", prevButton.disabled)
        }
        const nextButton = document.getElementById("video-next")
        if (nextButton) {
          nextButton.disabled = this.currentVideo === this.videoTargets.length - 1
          nextButton.classList.toggle("hidden", nextButton.disabled)
        }
      })
      playerBox.classList.remove("hidden")
    } else {
      playerBox.classList.add("hidden")
    }

    if (this.detailPaneOpen && videoTarget) {
      const videosPerRow = this.computeColumnsPerRow()
      const moveToRow = 1 + Math.ceil((this.currentVideo + 1) / videosPerRow)
      playerBox.style.gridRow = moveToRow

      videoTarget.scrollIntoView({ block: "center", behavior: "smooth" })
    }

    this.videoTargets.forEach((btn, i) => {
      const img = btn.querySelector("img")
      if (img) {
        const activeClass = "border-2"
        img.classList.toggle(activeClass, i === this.currentVideo && this.detailPaneOpen)
      }
    })
  }

  computeColumnsPerRow() {
    if (this.videoTargets.length === 0) return 1

    const first = this.videoTargets[0]
    const grid = first.parentElement
    if (!grid) return 1

    const gridRect = grid.getBoundingClientRect()
    const itemRect = first.getBoundingClientRect()
    const columnGap = parseFloat(getComputedStyle(grid).columnGap) || 0
    const itemWidth = itemRect.width + columnGap

    if (itemWidth === 0) return 1

    return Math.max(1, Math.round(gridRect.width / itemWidth))
  }

  fetchPlayer(url) {
    return fetch(url)
      .then((response) => {
        if (!response.ok) throw new Error(response.statusText)
        return response.text()
      })
      .then((html) => {
        this.playerBoxTarget.innerHTML = html
      })
      .catch((error) => {
        this.playerBoxTarget.innerHTML = "<p class='p-8 text-center text-cerise'>Error loading video</p>"
      })
  }
}
