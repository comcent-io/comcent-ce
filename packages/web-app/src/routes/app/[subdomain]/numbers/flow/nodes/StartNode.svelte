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

<!-- Start keeps a canvas row to itself: the other nodes are saved as offsets
     from where they fall in the rows below, so they must not move up beside it.
     The outlet fills its parent, so its width is set by the inner box. -->
<div class="w-full">
  <div class="w-[17rem]">
    <Outlet nodeId="_start" {selectedOutlet} {connected} {onOutletSelected} {onDisconnectOutlet}>
      <h4 class="text-lg font-bold dark:text-white">Start</h4>
      <p class="mt-1 text-sm text-slate-600 dark:text-slate-300">Every call begins here.</p>
    </Outlet>
  </div>
</div>
