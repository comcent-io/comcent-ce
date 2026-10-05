<script lang="ts" module>
  export type PillTone = 'gray' | 'cyan' | 'green' | 'amber' | 'red' | 'blue';
</script>

<script lang="ts">
  import type { Snippet } from 'svelte';

  // A small rounded label for a status or a tag, e.g. "Inbound", "Positive",
  // a call's labels. `dot` puts a coloured dot before the text.
  interface Props {
    tone?: PillTone;
    dot?: boolean;
    children?: Snippet;
  }

  let { tone = 'gray', dot = false, children }: Props = $props();

  const tones: Record<PillTone, { pill: string; dot: string }> = {
    gray: {
      pill: 'bg-slate-100 text-slate-700 ring-slate-200 dark:bg-slate-700/60 dark:text-slate-200 dark:ring-slate-600',
      dot: 'bg-slate-400',
    },
    cyan: {
      pill: 'bg-cyan-50 text-cyan-800 ring-cyan-200 dark:bg-cyan-900/40 dark:text-cyan-200 dark:ring-cyan-800',
      dot: 'bg-cyan-500',
    },
    green: {
      pill: 'bg-green-50 text-green-800 ring-green-200 dark:bg-green-900/40 dark:text-green-200 dark:ring-green-800',
      dot: 'bg-green-500',
    },
    amber: {
      pill: 'bg-amber-50 text-amber-800 ring-amber-200 dark:bg-amber-900/40 dark:text-amber-200 dark:ring-amber-800',
      dot: 'bg-amber-500',
    },
    red: {
      pill: 'bg-red-50 text-red-800 ring-red-200 dark:bg-red-900/40 dark:text-red-200 dark:ring-red-800',
      dot: 'bg-red-500',
    },
    blue: {
      pill: 'bg-blue-50 text-blue-800 ring-blue-200 dark:bg-blue-900/40 dark:text-blue-200 dark:ring-blue-800',
      dot: 'bg-blue-500',
    },
  };
</script>

<span
  class="inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 ring-inset {tones[
    tone
  ].pill}"
>
  {#if dot}
    <span class="h-1.5 w-1.5 rounded-full {tones[tone].dot}" aria-hidden="true"></span>
  {/if}
  {@render children?.()}
</span>
