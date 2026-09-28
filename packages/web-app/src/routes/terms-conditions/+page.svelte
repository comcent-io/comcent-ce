<script lang="ts">
  import { goto } from '$app/navigation';
  import { postJson } from '$lib/http';

  let { data } = $props();

  let saving = $state(false);
  let errorMessage = $state('');

  async function acceptTerms(event: Event) {
    event.preventDefault();
    saving = true;
    errorMessage = '';

    const result = await postJson('/api/v2/user/accept-terms', {});
    if (!result.ok) {
      errorMessage = result.error;
      saving = false;
      return;
    }

    await goto('/org');
  }
</script>

<section class="bg-gray-50 dark:bg-gray-900">
  <div class="flex flex-col items-center justify-center px-6 py-8 mx-auto md:h-screen lg:py-0">
    <form method="POST" class="mt-3 mr-2" onsubmit={acceptTerms}>
      <div
        class="max-w-lg p-6 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700"
      >
        <h5 class="mb-2 text-2xl font-bold tracking-tight text-gray-900 dark:text-white">
          Terms of Use and Privacy Policy
        </h5>
        {#if data.terms.previouslyAccepted}
          <p class="mb-3 font-normal text-gray-700 dark:text-gray-400">
            We've updated our Terms of Use and Privacy Policy. Please review and accept them to
            continue.
          </p>
        {/if}
        <p class="mb-3 font-normal text-gray-700 dark:text-gray-400">
          I accept the <a
            href={data.terms.termsUrl}
            target="_blank"
            rel="noopener noreferrer"
            class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
          >
            Terms of Use
          </a>
          and
          <a
            href={data.terms.privacyUrl}
            target="_blank"
            rel="noopener noreferrer"
            class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
          >
            Privacy Policy
          </a>
        </p>

        {#if errorMessage}
          <p class="mb-3 text-sm text-red-600 dark:text-red-400">{errorMessage}</p>
        {/if}

        <button
          type="submit"
          disabled={saving}
          class="px-3 py-2 text-sm font-medium text-center text-white bg-blue-700 rounded-lg hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
        >
          {saving ? 'Saving...' : 'I accept'}
        </button>
      </div>
    </form>
  </div>
</section>
