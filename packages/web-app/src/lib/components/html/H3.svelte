<script lang="ts">
  interface Props {
    className?: string;
    children?: import('svelte').Snippet;
  }

  let { className = '', children }: Props = $props();
</script>

<h3 class="text-3xl font-bold dark:text-white {className}">
  {@render children?.()}
</h3>
