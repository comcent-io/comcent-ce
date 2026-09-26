<script lang="ts">
  interface Props {
    className?: string;
    children?: import('svelte').Snippet;
  }

  let { className = '', children }: Props = $props();
</script>

<p class="text-gray-500 dark:text-gray-400 {className}">
  {@render children?.()}
</p>
