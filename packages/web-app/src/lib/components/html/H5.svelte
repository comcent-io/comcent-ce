<script>
  /**
   * @typedef {Object} Props
   * @property {import('svelte').Snippet} [children]
   */

  /** @type {Props} */
  let { children } = $props();
</script>

<h5 class="text-xl font-bold dark:text-white">
  {@render children?.()}
</h5>
