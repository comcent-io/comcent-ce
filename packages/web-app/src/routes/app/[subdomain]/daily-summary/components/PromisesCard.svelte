<script lang="ts">
  export let totalPromisesCreated: number = 0;
  export let totalPromisesClosed: number = 0;
</script>

<div
  class="bg-gray-800 dark:bg-gray-800 rounded-lg p-6 border border-gray-700 dark:border-gray-700 min-h-[250px]"
>
  <h2 class="text-xl font-bold text-white mb-4">Promises</h2>
  <div class="space-y-4">
    <!-- Total Promises Created -->
    <div>
      <div class="mb-2">
        <span class="text-white text-sm font-medium">Created Today</span>
      </div>
      <div class="text-3xl font-bold text-white">
        {totalPromisesCreated}
      </div>
    </div>

    <!-- Total Promises Closed -->
    <div>
      <div class="mb-2">
        <span class="text-white text-sm font-medium">Total Closed</span>
      </div>
      <div class="text-3xl font-bold text-white">
        {totalPromisesClosed}
      </div>
    </div>
  </div>
</div>
