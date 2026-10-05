// The look of the form components in this folder: the same Flowbite style
// most forms already use. Only these components use it; pages use the
// components (Input, Textarea, Select, Checkbox, Label, Hint,
// SecondaryButton, Field ...), not the classes.

export const inputClass =
  'block w-full rounded-lg border border-gray-300 bg-gray-50 p-2.5 text-sm text-gray-900 placeholder-gray-400 focus:border-blue-500 focus:ring-blue-500 disabled:cursor-not-allowed disabled:opacity-60 aria-[invalid=true]:border-red-400 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder-gray-400 dark:focus:border-blue-500 dark:focus:ring-blue-500';

export const textareaClass = `${inputClass} min-h-28 leading-6`;

export const checkboxClass =
  'h-4 w-4 shrink-0 rounded border-gray-300 bg-gray-100 text-blue-600 focus:ring-2 focus:ring-blue-500 dark:border-gray-600 dark:bg-gray-700 dark:ring-offset-gray-800 dark:focus:ring-blue-600';

export const labelClass = 'mb-1.5 block text-sm font-medium text-gray-900 dark:text-white';

export const hintClass = 'mt-1.5 text-xs text-gray-500 dark:text-gray-400';

export const errorClass = 'mt-1.5 text-xs text-red-600 dark:text-red-400';

// A quiet secondary action, e.g. Cancel beside Save (SecondaryButton): its
// shape, its size, and its colour (red for a destructive one, e.g. a row's
// Delete).
export const secondaryActionBase =
  'inline-flex items-center justify-center rounded-lg border bg-white font-medium disabled:cursor-not-allowed disabled:opacity-60 dark:bg-gray-800';

export const secondaryActionSize = { md: 'px-5 py-2.5 text-sm', sm: 'px-3 py-2 text-sm' };

export const secondaryActionTone = {
  default:
    'border-gray-300 text-gray-700 hover:bg-gray-50 dark:border-gray-600 dark:text-gray-200 dark:hover:bg-gray-700',
  danger:
    'border-red-200 text-red-600 hover:bg-red-50 dark:border-red-900 dark:text-red-400 dark:hover:bg-red-900/30',
};
