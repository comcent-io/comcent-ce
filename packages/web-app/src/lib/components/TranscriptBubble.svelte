<script lang="ts">
  export let name = 'Elon Musk';
  export let message = "That's awesome. I think our users will really appreciate the improvements.";

  $: flexDirection = name?.startsWith('+') ? 'flex-row' : 'flex-row-reverse';
</script>

<div class="flex {flexDirection}">
  <div class="flex items-start gap-2.5 {flexDirection}">
    <img
      class="w-8 h-8 rounded-full"
      src="https://ui-avatars.com/api/?name={name}&rounded=true"
      alt="{name} image"
    />
    <div
      class="flex flex-col w-full max-w-[320px] leading-1.5 p-4 border-gray-200 bg-gray-200 rounded-e-xl rounded-es-xl dark:bg-gray-600"
    >
      <div class="flex items-center space-x-2 rtl:space-x-reverse">
        <span class="text-sm font-semibold text-gray-900 dark:text-white">{name}</span>
        <span class="text-sm font-normal text-gray-500 dark:text-gray-400">11:46</span>
      </div>
      <p class="text-sm font-normal py-2.5 text-gray-900 dark:text-white">
        {message}
      </p>
    </div>
  </div>
</div>
