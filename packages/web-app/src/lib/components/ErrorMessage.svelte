<script lang="ts">
  type ErrorObject = {
    message: string;
    formErrors: {
      message: string;
      path: string[];
    }[];
  };
  export let error: ErrorObject;
</script>

<div
  class="p-4 mb-4 text-sm text-red-800 rounded-lg bg-red-50 dark:bg-gray-800 dark:text-red-400 mt-2"
  role="alert"
>
  {#if error?.message}
    <p>{error?.message}</p>
  {/if}
  <ul class="max-w-md space-y-1 text-red-500 list-disc list-inside dark:text-red-400">
    {#each error?.formErrors ?? [] as e}
      <li>{e.path.join('.')}: {e.message}</li>
    {/each}
  </ul>
</div>
