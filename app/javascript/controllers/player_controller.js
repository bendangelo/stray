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
      const minWidths = [ 640, 768, 1024 ]
      const matchedWidths = minWidths.filter((width) => {
        return window.matchMedia(`(min-width: ${width}px)`).matches
      })
      const videosPerRow = 2 + matchedWidths.length
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
