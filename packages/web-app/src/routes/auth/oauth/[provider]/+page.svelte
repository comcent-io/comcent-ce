<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import { getJson } from '$lib/http';

  onMount(async () => {
    const { origin } = $page.url;
    const provider = $page.params.provider;
    const redirectUri = `${origin}/auth/callback/${provider}`;

    const result = await getJson<{ authUrl: string }>(
      `/api/v2/auth/oauth/${provider}/start?redirect_uri=${encodeURIComponent(redirectUri)}`,
    );
    if (!result.ok) {
      await goto('/login');
      return;
    }

    window.location.assign(result.data.authUrl);
  });
</script>

<p class="p-6 text-sm text-slate-600 dark:text-slate-300">Redirecting to sign in...</p>
