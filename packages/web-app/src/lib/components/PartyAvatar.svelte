<script lang="ts">
  import { isPhoneParty, partyInitials } from '$lib/party';

  // A call party's initials in a circle: slate for the customer (a phone
  // number), cyan for a member.
  interface Props {
    party: string;
  }

  let { party }: Props = $props();
</script>

<span
  class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-xs font-semibold {isPhoneParty(
    party,
  )
    ? 'bg-slate-200 text-slate-700 dark:bg-slate-600 dark:text-slate-100'
    : 'bg-cyan-100 text-cyan-800 dark:bg-cyan-900 dark:text-cyan-100'}"
  aria-hidden="true"
>
  {partyInitials(party)}
</span>
