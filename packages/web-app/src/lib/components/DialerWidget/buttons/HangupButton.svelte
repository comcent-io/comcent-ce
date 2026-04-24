<script>
  import PhoneDisconnectIcon from '$lib/components/Icons/PhoneDisconnectIcon.svelte';
</script>

<button
  type="button"
  on:click
  class="rounded-full mr-1 text-white bg-red-700 hover:bg-red-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium text-sm p-2.5 inline-flex justify-center items-center dark:bg-red-600 dark:hover:bg-red-700 dark:focus:ring-blue-800"
>
  <PhoneDisconnectIcon />
  <span class="sr-only">Hangup</span>
</button>
