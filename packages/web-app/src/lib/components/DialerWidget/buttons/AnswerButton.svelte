<script>
  import PhoneIcon from '$lib/components/Icons/PhoneIcon.svelte';
</script>

<button
  type="button"
  on:click
  class="rounded-full mr-1 text-white bg-green-700 hover:bg-green-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium text-sm p-2.5 inline-flex justify-center items-center dark:bg-green-600 dark:hover:bg-green-700 dark:focus:ring-blue-800"
>
  <PhoneIcon />
  <span class="sr-only">Answer</span>
</button>
