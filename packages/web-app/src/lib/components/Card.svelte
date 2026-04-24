<script lang="ts">
  export let className = '';
</script>

<div
  class="block p-6 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700 {className}"
>
  <slot />
</div>
