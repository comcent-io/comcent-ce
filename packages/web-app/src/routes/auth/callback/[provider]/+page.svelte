<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import { getJson } from '$lib/http';
  import { setSessionToken } from '$lib/session';

  onMount(async () => {
    const { origin, searchParams } = page.url;
    const provider = page.params.provider;
    const redirectUri = `${origin}/auth/callback/${provider}`;
    const callbackUrl =
      `/api/v2/auth/oauth/${provider}/callback?code=${encodeURIComponent(searchParams.get('code') || '')}` +
      `&state=${encodeURIComponent(searchParams.get('state') || '')}` +
      `&redirect_uri=${encodeURIComponent(redirectUri)}`;

    const result = await getJson<{ token: string }>(callbackUrl);
    if (!result.ok) {
      await goto('/login');
      return;
    }

    setSessionToken(result.data.token);
    await goto('/app', { invalidateAll: true });
  });
</script>

<p class="p-6 text-sm text-slate-600 dark:text-slate-300">Signing you in...</p>
