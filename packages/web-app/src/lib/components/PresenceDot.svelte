<script lang="ts">
  // The coloured dot for a member's presence, the same everywhere it shows
  // (the dialer's status pill, the dashboard).
  interface Props {
    presence: string;
    size?: 'sm' | 'md';
  }

  let { presence, size = 'sm' }: Props = $props();

  const colors: Record<string, string> = {
    'Logged Out': 'bg-gray-400 dark:bg-gray-500',
    Available: 'bg-green-500',
    'On Break': 'bg-amber-500',
    'On Call': 'bg-blue-500',
    'Wrap Up': 'bg-purple-500',
    Busy: 'bg-red-500',
  };
</script>

<span
  class="shrink-0 rounded-full {size === 'md' ? 'h-2.5 w-2.5' : 'h-2 w-2'} {colors[presence] ??
    'bg-gray-400'}"
  aria-hidden="true"
></span>
