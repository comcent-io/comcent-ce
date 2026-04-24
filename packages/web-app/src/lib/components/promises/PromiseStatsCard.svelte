<script lang="ts">
  export let icon: 'check' | 'chart' | 'user' | 'status';
  export let title: string;
  export let value: string | number;
  export let subtitle: string = '';
  export let color: 'blue' | 'green' | 'purple' = 'blue';

  const iconPaths = {
    check: 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z',
    chart:
      'M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z',
    user: 'M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z',
    status: 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z',
  };

  const colorClasses = {
    blue: {
      bg: 'bg-blue-100 dark:bg-blue-900',
      icon: 'text-blue-600 dark:text-blue-400',
    },
    green: {
      bg: 'bg-green-100 dark:bg-green-900',
      icon: 'text-green-600 dark:text-green-400',
    },
    purple: {
      bg: 'bg-purple-100 dark:bg-purple-900',
      icon: 'text-purple-600 dark:text-purple-400',
    },
  };
</script>

<div
  class="bg-white dark:bg-gray-800 rounded-lg shadow-sm border border-gray-200 dark:border-gray-700 p-6"
>
  <div class="flex items-center">
    <div class="flex-shrink-0">
      <div class="w-12 h-12 {colorClasses[color].bg} rounded-lg flex items-center justify-center">
        <svg
          class="w-6 h-6 {colorClasses[color].icon}"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d={iconPaths[icon]}
          ></path>
        </svg>
      </div>
    </div>
    <div class="ml-4 flex-1">
      <p class="text-sm font-medium text-gray-500 dark:text-gray-400">{title}</p>
      <p class="text-3xl font-bold text-gray-900 dark:text-white">{value}</p>
      {#if subtitle}
        <p class="text-xs text-gray-500 dark:text-gray-400">{subtitle}</p>
      {/if}
      <slot />
    </div>
  </div>
</div>
