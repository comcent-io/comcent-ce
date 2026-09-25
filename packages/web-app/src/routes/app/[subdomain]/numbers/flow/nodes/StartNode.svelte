<script lang="ts">
  import type { SelectedOutlet } from '../SelectedOutlet';
  import Outlet from '../utils/Outlet.svelte';

  interface Props {
    selectedOutlet: SelectedOutlet | null;
    connected?: boolean;
    onOutletSelected?: (outlet: SelectedOutlet) => void;
    onDisconnectOutlet?: (outlet: SelectedOutlet) => void;
  }

  let { selectedOutlet, connected = false, onOutletSelected, onDisconnectOutlet }: Props = $props();
</script>

<Outlet
  nodeId="_start"
  {selectedOutlet}
  {connected}
  {onOutletSelected}
  {onDisconnectOutlet}
  class="block w-[15rem] rounded-xl border-2 border-amber-400 bg-white p-4 shadow dark:border-amber-400 dark:bg-gray-800"
>
  <h4 class="text-lg font-bold dark:text-white">Start</h4>
  <p class="mt-1 text-sm text-slate-600 dark:text-slate-300">
    Begin here, then connect this output to the first step in the call flow.
  </p>
</Outlet>
