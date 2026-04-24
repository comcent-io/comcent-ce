<script lang="ts">
  import { page } from '$app/stores';
</script>

<h3 class="text-3xl font-bold dark:text-white">Compliance</h3>

<ul
  class="mt-4 max-w-sm mb-4 mx-auto flex flex-wrap justify-between text-lg font-medium text-center text-black border-b border-gray-200 dark:border-gray-700 dark:text-gray-200"
>
  <li class="me-2">
    <a
      href={`/app/${$page.params.subdomain}/settings/compliance/search`}
      class="inline-block p-4 rounded-t-lg hover:text-gray-600 hover:bg-gray-50 dark:hover:bg-gray-800 dark:hover:text-gray-300 w-40"
    >
      Search
    </a>
  </li>
  <li class="me-2">
    <a
      href={`/app/${$page.params.subdomain}/settings/compliance/status`}
      class="inline-block p-4 rounded-t-lg hover:text-gray-600 hover:bg-gray-50 dark:hover:bg-gray-800 dark:hover:text-gray-300 w-40"
    >
      Status
    </a>
  </li>
</ul>
