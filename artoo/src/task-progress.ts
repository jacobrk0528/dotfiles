// Explicit memory for repeated inspections. A visited item and its observed finding
// survive back-navigation, table reordering and planner retries.
export type Finding = { key: string; result: string; evidence: string[]; observation: string };
export type ProgressUpdate = { discovered: string[]; checked: Omit<Finding, "observation">[]; list_complete: boolean };
export const PROGRESS_SCHEMA = {
  type: "object", additionalProperties: false, required: ["discovered", "checked", "list_complete"],
  properties: {
    discovered: { type: "array", items: { type: "string" } },
    checked: {
      type: "array", maxItems: 1,
      items: {
        type: "object", additionalProperties: false, required: ["key", "result", "evidence"],
        properties: { key: { type: "string" }, result: { type: "string" }, evidence: { type: "array", minItems: 1, items: { type: "string" } } },
      },
    },
    list_complete: { type: "boolean" },
  },
};
const normalize = (s: string) => s.trim().replace(/\s+/g, " ").toLowerCase();

export class TaskProgress {
  private items = new Map<string, { key: string; finding?: Finding }>();
  listComplete = false;

  discover(keys: string[]) {
    for (const key of keys) if (key.trim() && !this.items.has(normalize(key))) this.items.set(normalize(key), { key: key.trim() });
  }

  record(finding: Finding) {
    this.discover([finding.key]);
    this.items.get(normalize(finding.key))!.finding = finding;
  }

  static supportedByText(finding: Omit<Finding, "observation">, content: string) {
    const text = normalize(content);
    return !!finding.key && !!finding.result && finding.evidence.length > 0 &&
      [finding.key, finding.result, ...finding.evidence].every((quote) => !!quote.trim() && text.includes(normalize(quote)));
  }

  snapshot() {
    const all = [...this.items.values()];
    return { discovered: all.map((i) => i.key), pending: all.filter((i) => !i.finding).map((i) => i.key), checked: all.flatMap((i) => i.finding ? [i.finding] : []), list_complete: this.listComplete };
  }

  completionBlocker(): string | null {
    const { discovered, pending } = this.snapshot();
    if (!discovered.length) return null;
    if (pending.length) return `Still unchecked: ${pending.join(", ")}. Continue with the next pending item; do not restart checked items.`;
    if (!this.listComplete) return "All discovered items were checked, but the list has not been inspected to its end. Scroll/page through the list for remaining items.";
    return null;
  }

  /** Why the checklist isn't finished, worded for the user (completionBlocker is for the planner). */
  openItems(): string {
    const { pending } = this.snapshot();
    if (pending.length) return `${pending.length} listed item${pending.length === 1 ? " was" : "s were"} never individually checked.`;
    return "the list was not inspected to its end.";
  }

  partialSummary() {
    const { checked, pending } = this.snapshot();
    return checked.length ? ` Verified so far: ${checked.map((f) => `${f.key}: ${f.result}`).join("; ")}. ${pending.length} discovered items remain unchecked${this.listComplete ? "." : "; the rest of the list may contain more."}` : "";
  }
}
