<script lang="ts">
  import moment from 'moment-timezone';

  export let caller: string;
  export let callee: string;
  export let direction: string;
  export let startAt: string;

  function getDisplayName(currentParty: string): string {
    if (currentParty.startsWith('+')) return currentParty;
    return currentParty.split('@')[0].split('_')[0];
  }
</script>

<div
  class="bg-slate-100 dark:bg-gray-800 rounded-lg shadow-sm border border-slate-400 dark:border-gray-700 p-5 mb-4"
>
  <div class="flex flex-wrap items-center justify-between gap-4">
    <!-- Caller Info -->
    <div class="flex items-center space-x-3">
      <div class="bg-blue-600 rounded-full p-3 shadow-lg">
        <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z"
          ></path>
        </svg>
      </div>
      <div>
        <p class="text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wide">
          From
        </p>
        <p class="text-base font-bold text-gray-900 dark:text-white">
          {getDisplayName(caller)}
        </p>
      </div>
    </div>

    <!-- Direction Arrow -->
    <div class="flex items-center">
      <svg
        class="w-6 h-6 text-slate-400 dark:text-slate-500"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M13 7l5 5m0 0l-5 5m5-5H6"
        ></path>
      </svg>
    </div>

    <!-- Callee Info -->
    <div class="flex items-center space-x-3">
      <div class="bg-emerald-600 rounded-full p-3 shadow-lg">
        <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
          ></path>
        </svg>
      </div>
      <div>
        <p class="text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wide">
          To
        </p>
        <p class="text-base font-bold text-gray-900 dark:text-white">
          {getDisplayName(callee)}
        </p>
      </div>
    </div>

    <!-- Metadata -->
    <div class="flex items-center space-x-3 ml-auto">
      <div class="flex items-center space-x-2 bg-slate-200 dark:bg-gray-700 rounded-lg px-3 py-2">
        <svg
          class="w-4 h-4 text-slate-600 dark:text-slate-400"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
          ></path>
        </svg>
        <span class="text-xs font-medium text-slate-700 dark:text-slate-300">
          {moment(startAt).format('MMM DD, YYYY • hh:mm A')}
        </span>
      </div>
      <div class="bg-violet-600 rounded-lg px-3 py-2 shadow-sm">
        <span class="text-xs font-bold text-white uppercase tracking-wider">
          {direction}
        </span>
      </div>
    </div>
  </div>
</div>
