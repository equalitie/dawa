import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.handle.addEventListener("mousedown", this.startDrag);
    this.startX = 0;
    this.startWidth = 0;
    this.hasMoved = false;
    this.dragThreshold = 3; // pixels of movement to consider it a drag
  }

  disconnect() {
    this.handle.removeEventListener("mousedown", this.startDrag);
    document.removeEventListener("mousemove", this.drag);
    document.removeEventListener("mouseup", this.endDrag);
  }

  setWidth(newWidth) {
    newWidth = newWidth % 2 === 0 ? newWidth : newWidth + 1;
    // ^^ force width to be even so that when width of the whole body is distributed
    // the split handle does not have a weird subpixel width that makes it change size
    document.documentElement.style.setProperty(
      "--sidebar-width",
      `${newWidth}px`,
    );
  }

  startDrag = (e) => {
    e.preventDefault();
    this.startX = e.clientX;
    this.startY = e.clientY;
    this.startWidth = parseInt(window.getComputedStyle(this.sidebar).width, 10);
    this.hasMoved = false;

    document.addEventListener("mousemove", this.drag);
    document.addEventListener("mouseup", this.endDrag);
  };

  drag = (e) => {
    const deltaX = Math.abs(e.clientX - this.startX);
    const deltaY = Math.abs(e.clientY - this.startY);
    if (
      !this.hasMoved &&
      (deltaX > this.dragThreshold || deltaY > this.dragThreshold)
    ) {
      this.hasMoved = true;
    }

    if (!this.startX) return;

    let newWidth = Math.round(this.startWidth + (e.clientX - this.startX));
    this.setWidth(newWidth);
  };

  endDrag = (e) => {
    document.removeEventListener("mousemove", this.drag);
    document.removeEventListener("mouseup", this.endDrag);
    if (!this.hasMoved) {
      this.onClick(e);
    }
    this.startX = 0;
    this.hasMoved = false;
  };

  onClick = (e) => {
    if (this.startWidth <= 100) {
      const width = this.priorWidth || 250;
      this.setWidth(width);
    } else {
      this.priorWidth = this.startWidth;
      this.setWidth(0);
    }
  };

  get sidebar() {
    return document.getElementById("sidebar");
  }

  get handle() {
    return this.element;
  }
}
