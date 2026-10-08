// A call label as the Call Story filter sees it. Org labels saved from the AI
// settings have only a name, so the name is the key when there is no id.
export interface FilterLabel {
  id?: string | number | null;
  name: string;
}

export function labelKey(label: FilterLabel): string {
  return String(label.id || label.name);
}

// Apply has something to do whenever the ticked labels differ from the
// applied ones, including unticking every label of an applied filter, which
// shows all calls again.
export function selectionChanged(selectedKeys: string[], appliedKeys: string[]): boolean {
  const applied = new Set(appliedKeys);
  const selected = new Set(selectedKeys);
  return selected.size !== applied.size || [...selected].some((key) => !applied.has(key));
}
