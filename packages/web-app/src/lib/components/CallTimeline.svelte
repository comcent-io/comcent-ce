<script lang="ts">
  import moment from 'moment-timezone';

  export let callDuration: number;
  export let scale: number;

  // Timeline calculations
  let timelineMarkers: Array<{ time: number; label: string; position: number }> = [];

  $: {
    if (callDuration > 0) {
      // Calculate timeline width
      const timelineWidth = callDuration * scale;

      // Calculate initial time unit based on call duration
      // For short calls: larger time differences
      // For long calls: smaller time differences
      let timeUnit: number;

      if (callDuration <= 60) {
        // Short calls (≤1 minute): 15-30s differences
        timeUnit = Math.max(15, Math.ceil(callDuration / 4));
      } else if (callDuration <= 300) {
        // Medium calls (≤5 minutes): 10-25s differences
        timeUnit = Math.max(10, Math.ceil(callDuration / 12));
      } else if (callDuration <= 1800) {
        // Long calls (≤30 minutes): 5-15s differences
        timeUnit = Math.max(5, Math.ceil(callDuration / 120));
      } else {
        // Very long calls (>30 minutes): 5-10s differences
        timeUnit = Math.max(5, Math.ceil(callDuration / 360));
      }

      // Apply scale-based adjustments
      if (scale <= 1) {
        // At zoom level 1, use larger time units to prevent label overlap
        timeUnit = Math.max(timeUnit, 30);
      } else if (scale >= 5) {
        timeUnit = Math.min(timeUnit, 10);
      } else {
        // Linear interpolation between scale 1 and 5
        const scaleAdjustedTimeUnit = 30 - (scale - 1) * 5;
        timeUnit = Math.min(timeUnit, scaleAdjustedTimeUnit);
      }

      // For scales beyond 5, continue the proportional decrease but ensure minimum of 5s
      if (scale > 5) {
        const scaleAdjustedTimeUnit = Math.max(5, 10 - (scale - 5) * 1);
        timeUnit = Math.min(timeUnit, scaleAdjustedTimeUnit);
      }

      // Ensure time unit is a multiple of 5
      timeUnit = Math.ceil(timeUnit / 5) * 5;

      // Calculate number of markers
      const numMarkers = Math.ceil(callDuration / timeUnit);

      // Ensure we don't have too many markers (max 15 at scale 1, 30 otherwise)
      const maxMarkers = scale <= 1 ? 15 : 30;
      if (numMarkers > maxMarkers) {
        timeUnit = Math.ceil(callDuration / maxMarkers);
        timeUnit = Math.ceil(timeUnit / 5) * 5; // Ensure it's still a multiple of 5
      }

      // Additional check for minimum spacing between markers to prevent label overlap
      // At scale 1, ensure at least 40px between markers (assuming average label width of 30px + 10px padding)
      if (scale <= 1) {
        const minTimeUnitForSpacing = Math.ceil((40 / scale) * (callDuration / 100));
        if (timeUnit < minTimeUnitForSpacing) {
          timeUnit = minTimeUnitForSpacing;
          timeUnit = Math.ceil(timeUnit / 5) * 5; // Ensure it's still a multiple of 5
        }
      }

      timelineMarkers = [];

      // Only add markers if we have more than one marker
      if (numMarkers > 1) {
        // Always start with 0s marker at the left edge
        timelineMarkers.push({
          time: 0,
          label: formatTime(0),
          position: 0,
        });

        // Add other markers
        for (let i = 1; i <= numMarkers; i++) {
          const time = i * timeUnit;
          // Ensure marker doesn't go beyond call duration
          if (time <= callDuration) {
            timelineMarkers.push({
              time,
              label: formatTime(time),
              position: (time / callDuration) * 100,
            });
          }
        }

        // Ensure the last marker is exactly at the end if it's close
        const lastMarker = timelineMarkers[timelineMarkers.length - 1];
        if (lastMarker && callDuration - lastMarker.time < timeUnit) {
          // Replace the last marker with the exact end time
          timelineMarkers[timelineMarkers.length - 1] = {
            time: callDuration,
            label: formatTime(callDuration),
            position: 100,
          };
        }
      }
    }
  }

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

<div
  class="inline-block absolute bg-gray-100 dark:bg-gray-900 border border-gray-200 dark:border-gray-600 rounded-lg p-4"
  style="transform: translateX({0 * scale}px); width: {callDuration *
    scale}px; height: 60px; display: inline-block;"
>
  <!-- Timeline line -->
  <div
    class="absolute top-1/2 left-0 right-0 h-px bg-gray-400 dark:bg-gray-500 transform -translate-y-1/2"
  ></div>

  <!-- Timeline markers -->
  {#each timelineMarkers as marker}
    <div class="absolute top-0 bottom-0 flex flex-col" style="left: {marker.position}%">
      <!-- Marker line -->
      <div class="w-px h-1/2 bg-blue-500 dark:bg-blue-300"></div>
      <!-- Time label -->
      <div class="text-xs text-gray-700 dark:text-gray-200 mt-3 whitespace-nowrap font-medium">
        {marker.label}
      </div>
    </div>
  {/each}
</div>
