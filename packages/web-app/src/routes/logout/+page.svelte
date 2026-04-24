<script lang="ts">
  import { onMount } from 'svelte';

  let logoutForm: HTMLFormElement;

  onMount(() => {
    logoutForm.submit();
  });
</script>

<h1>Logging out...</h1>
<form method="POST" bind:this={logoutForm}></form>
