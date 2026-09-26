<script>
  /**
   * @typedef {Object} Props
   * @property {import('svelte').Snippet} [children]
   */

  /** @type {Props} */
  let { children } = $props();
</script>

<h6 class="text-lg font-bold dark:text-white">
  {@render children?.()}
</h6>
