// Screen text → clickable candidates for non-browser windows. Local only.
// RapidOCR (PaddleOCR models on ONNX) via a uv inline-deps script; tesseract missed
// light-on-dark buttons entirely (e.g. Looker's white-on-blue "Edit").
import { join } from "node:path";
import { run } from "../exec.ts";

export type Element = { text: string; x: number; y: number; w: number; h: number; conf: number };

const SCRIPT = join(import.meta.dir, "..", "..", "ocr", "rapid_ocr.py");

type RapidBox = { text: string; conf: number; box: [number, number, number, number] };

/** Map RapidOCR boxes from image pixels back to layout coordinates. */
export function toElements(boxes: RapidBox[], scale: number, offset: { x: number; y: number }): Element[] {
  return boxes.map(({ text, conf, box: [x, y, w, h] }) => ({
    text: text.trim(),
    conf,
    x: x / scale + offset.x,
    y: y / scale + offset.y,
    w: w / scale,
    h: h / scale,
  }));
}

/** Drop OCR noise and bare numbers/metrics (they're rarely click targets and are data, not UI). */
export function isUsefulLabel(e: Element): boolean {
  return e.conf >= 0.6 && (e.text.match(/[a-z]/gi) ?? []).length >= 2;
}

export async function ocr(png: string, scale: number, offset: { x: number; y: number }, labelsOnly = true): Promise<Element[]> {
  const out = await run(["uv", "run", "--quiet", "--script", SCRIPT, png]);
  const elements = toElements(JSON.parse(out) as RapidBox[], scale, offset);
  return labelsOnly ? elements.filter(isUsefulLabel) : elements.filter((e) => e.conf >= 0.5 && e.text.length > 0);
}
