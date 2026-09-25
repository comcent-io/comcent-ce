<script>
  /**
   * @typedef {Object} Props
   * @property {import('svelte').Snippet} [children]
   */

  /** @type {Props} */
  let { children } = $props();
</script>

<h2 class="text-4xl font-bold dark:text-white">
  {@render children?.()}
</h2>
