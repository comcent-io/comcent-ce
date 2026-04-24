<script lang="ts">
  export let data;
</script>

<section class="bg-white dark:bg-gray-900">
  <div class="py-8 px-4 mx-auto max-w-screen-xl lg:py-16 lg:px-6">
    <div class="mx-auto max-w-screen-sm text-center">
      <h1
        class="mb-4 text-4xl tracking-tight font-extrabold lg:text-5xl text-primary-600 dark:text-primary-500"
      >
        Account with same email ({data.user.email}) found.
      </h1>
      <p class="mb-4 text-lg font-light text-gray-500 dark:text-gray-400">
        Please try different method to login. You have logged with different method previously
        (Password or Google)
      </p>
      <form method="POST" action="/logout">
        <button
          class="inline-flex text-white bg-primary-600 hover:bg-primary-800 focus:ring-4 focus:outline-none focus:ring-primary-300 font-medium rounded-lg text-sm px-5 py-2.5 text-center dark:focus:ring-primary-900 my-4"
        >
          Sign out
        </button>
      </form>
    </div>
  </div>
</section>
