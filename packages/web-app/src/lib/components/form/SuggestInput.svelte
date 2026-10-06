<script lang="ts">
  import CloseIcon from '$lib/components/Icons/CloseIcon.svelte';
  import { inputClass } from './classes';

  // A text input whose suggestions open in a list attached right under it.
  // Given `values`, it holds several picks: each shows as a chip inside the
  // same box, in front of the text being typed. The caller supplies the
  // suggestions (fetch them in `oninput`) and decides in `onadd` whether typed
  // text may join the picks.
  interface Props {
    id: string;
    /** The text in the box; without `values`, this is the field's value. */
    value?: string;
    /** The picks, for a field that takes several. */
    values?: string[];
    suggestions?: string[];
    placeholder?: string;
    invalid?: boolean;
    oninput?: (text: string) => void;
    /** Enter on typed text, when the field takes several picks. */
    onadd?: (text: string) => void;
  }

  let {
    id,
    value = $bindable(''),
    values = $bindable(),
    suggestions = [],
    placeholder = '',
    invalid = false,
    oninput,
    onadd,
  }: Props = $props();

  let input: HTMLInputElement | undefined = $state();
  let open = $state(false);
  let active = $state(-1);

  let listed = $derived(open && suggestions.length > 0);

  function pick(suggestion: string) {
    if (values) {
      if (!values.includes(suggestion)) values = [...values, suggestion];
      value = '';
    } else {
      value = suggestion;
    }
    open = false;
    active = -1;
    input?.focus();
  }

  function remove(index: number) {
    values = values?.filter((_, i) => i !== index);
    input?.focus();
  }

  function onkeydown(event: KeyboardEvent) {
    if (event.key === 'ArrowDown' && listed) {
      event.preventDefault();
      active = (active + 1) % suggestions.length;
    } else if (event.key === 'ArrowUp' && listed) {
      event.preventDefault();
      active = (active - 1 + suggestions.length) % suggestions.length;
    } else if (event.key === 'Enter') {
      if (listed && active >= 0) {
        event.preventDefault();
        pick(suggestions[active]);
      } else if (values && value.trim() !== '') {
        event.preventDefault();
        onadd?.(value.trim());
      }
    } else if (event.key === 'Escape' && listed) {
      // Close the list only, not the dialog the field may be in.
      event.stopPropagation();
      open = false;
    } else if (event.key === 'Backspace' && value === '' && values?.length) {
      remove(values.length - 1);
    }
  }

  function handleInput() {
    open = true;
    active = -1;
    oninput?.(value);
  }
</script>

{#snippet textInput(className: string)}
  <input
    bind:this={input}
    {id}
    type="text"
    autocomplete="off"
    role="combobox"
    aria-expanded={listed}
    aria-controls={`${id}-suggestions`}
    aria-autocomplete="list"
    aria-invalid={invalid || undefined}
    {placeholder}
    bind:value
    oninput={handleInput}
    {onkeydown}
    onblur={() => (open = false)}
    class={className}
  />
{/snippet}

<div class="relative">
  {#if values}
    <!-- The box looks like one input; a click anywhere in it goes to the text. -->
    <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
    <div
      class="{inputClass} flex cursor-text flex-wrap items-center gap-1.5 focus-within:border-blue-500 focus-within:ring-1 focus-within:ring-blue-500"
      aria-invalid={invalid || undefined}
      onclick={() => input?.focus()}
    >
      {#each values as picked, index (picked)}
        <span
          class="inline-flex items-center gap-1 rounded-md bg-blue-100 py-0.5 pl-2 pr-1 text-xs font-medium text-blue-800 dark:bg-blue-900/60 dark:text-blue-200"
        >
          {picked}
          <button
            type="button"
            aria-label={`Remove ${picked}`}
            class="inline-flex h-4 w-4 items-center justify-center rounded hover:bg-blue-200 dark:hover:bg-blue-800 [&>svg]:h-2 [&>svg]:w-2"
            onclick={(event) => {
              event.stopPropagation();
              remove(index);
            }}
          >
            <CloseIcon />
          </button>
        </span>
      {/each}
      {@render textInput(
        'min-w-[9rem] flex-1 border-0 bg-transparent p-0 text-sm text-gray-900 placeholder-gray-400 focus:ring-0 dark:text-white',
      )}
    </div>
  {:else}
    {@render textInput(inputClass)}
  {/if}

  {#if listed}
    <ul
      id={`${id}-suggestions`}
      role="listbox"
      class="absolute left-0 right-0 top-full z-20 mt-1 max-h-48 overflow-auto rounded-lg border border-gray-200 bg-white py-1 shadow-lg dark:border-gray-600 dark:bg-gray-700"
    >
      {#each suggestions as suggestion, index (suggestion)}
        <li role="option" aria-selected={index === active}>
          <!-- mousedown would blur the input and close the list before the click lands. -->
          <button
            type="button"
            tabindex="-1"
            class="block w-full truncate px-3 py-2 text-left text-sm text-gray-900 hover:bg-gray-100 dark:text-white dark:hover:bg-gray-600 {index ===
            active
              ? 'bg-gray-100 dark:bg-gray-600'
              : ''}"
            onmousedown={(event) => event.preventDefault()}
            onclick={() => pick(suggestion)}
          >
            {suggestion}
          </button>
        </li>
      {/each}
    </ul>
  {/if}
</div>
