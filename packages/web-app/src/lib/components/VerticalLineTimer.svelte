<script lang="ts">
  import moment from 'moment-timezone';

  export let isVisible: boolean;
  export let position: number;
  export let currentTime: number;

  function formatTime(seconds: number): string {
    const duration = moment.duration(seconds, 'seconds');

    if (seconds < 60) {
      return `${seconds}s`;
    } else if (seconds < 3600) {
      const minutes = Math.floor(duration.asMinutes());
      const remainingSeconds = duration.seconds();
      return `${minutes}m${remainingSeconds > 0 ? ` ${remainingSeconds}s` : ''}`;
    } else {
      const hours = Math.floor(duration.asHours());
      const minutes = duration.minutes();
      return `${hours}h${minutes > 0 ? ` ${minutes}m` : ''}`;
    }
  }
</script>

{#if isVisible}
  <div
    class="absolute top-0 w-0.5 bg-red-500 pointer-events-none z-10"
    style="left: {position}%; height: 90%;"
  >
    <!-- Time tooltip -->
    <div
      class="absolute top-0 left-1/2 transform -translate-x-1/2 mt-2 px-2 py-1 bg-gray-900 text-white text-xs rounded shadow-lg whitespace-nowrap"
    >
      <div class="font-medium">{formatTime(currentTime)}</div>
    </div>
  </div>
{/if}
