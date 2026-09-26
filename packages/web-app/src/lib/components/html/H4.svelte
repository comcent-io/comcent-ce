<script>
  /**
   * @typedef {Object} Props
   * @property {import('svelte').Snippet} [children]
   */

  /** @type {Props} */
  let { children } = $props();
</script>

<h4 class="text-2xl font-bold dark:text-white">
  {@render children?.()}
</h4>
