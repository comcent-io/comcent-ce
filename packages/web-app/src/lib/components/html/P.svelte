<script lang="ts">
  export let className = '';
</script>

<p class="text-gray-500 dark:text-gray-400 {className}">
  <slot />
</p>
