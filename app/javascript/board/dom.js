// Tiny element builder: h("div", { class: "x", onclick: fn, dataset: { id: 1 } }, child, "text", [more])
export function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag)
  for (const [key, value] of Object.entries(attrs || {})) {
    if (value === undefined || value === null || value === false) continue
    if (key === "class") el.className = value
    else if (key === "dataset") Object.assign(el.dataset, value)
    else if (key === "style" && typeof value === "object") {
      for (const [prop, v] of Object.entries(value)) el.style.setProperty(prop.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`), v)
    }
    else if (key.startsWith("on")) el.addEventListener(key.slice(2), value)
    else if (value === true) el.setAttribute(key, "")
    else el.setAttribute(key, value)
  }
  append(el, children)
  return el
}

// replaceChildren() for a list that may contain null/false placeholders.
export function fill(el, ...children) {
  el.replaceChildren()
  append(el, children)
}

function append(el, children) {
  for (const child of children) {
    if (child === undefined || child === null || child === false) continue
    if (Array.isArray(child)) append(el, child)
    else el.append(child instanceof Node ? child : document.createTextNode(String(child)))
  }
}
