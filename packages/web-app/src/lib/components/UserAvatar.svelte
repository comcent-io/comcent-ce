<script lang="ts">
  // A user's profile picture, or their initials when they have none (people
  // who signed up with email and password) or it fails to load.
  interface Props {
    picture?: string | null;
    name?: string | null;
    email?: string | null;
    size?: 'sm' | 'lg';
    class?: string;
  }

  let { picture, name, email, size = 'sm', class: extra = '' }: Props = $props();

  let failed = $state(false);

  let initials = $derived(
    (name || email || '?')
      .split(/[\s@._-]+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0])
      .join('')
      .toUpperCase(),
  );

  let sizeClass = $derived(size === 'lg' ? 'h-24 w-24 text-3xl' : 'h-8 w-8 text-xs');
</script>

{#if picture && !failed}
  <!-- Google's photo links refuse requests that carry a referrer. -->
  <img
    class="{sizeClass} rounded-full object-cover {extra}"
    src={picture}
    alt={name ?? 'Profile'}
    referrerpolicy="no-referrer"
    onerror={() => (failed = true)}
  />
{:else}
  <span
    class="flex {sizeClass} shrink-0 items-center justify-center rounded-full bg-cyan-100 font-semibold text-cyan-800 dark:bg-cyan-900 dark:text-cyan-100 {extra}"
    role="img"
    aria-label={name ?? 'Profile'}
  >
    {initials}
  </span>
{/if}
