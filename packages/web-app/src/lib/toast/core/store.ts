import { get, writable, type Writable } from 'svelte/store';
import writableDerived from 'svelte-writable-derived';
import type { DefaultToastOptions, Toast, ToastType } from './types';

const TOAST_LIMIT = 20;

export const toasts: Writable<Toast[]> = writable([]);
export const pausedAt: Writable<number | null> = writable(null);

const toastTimeouts = new Map<Toast['id'], ReturnType<typeof setTimeout>>();

const addToRemoveQueue = (toastId: Toast['id']) => {
  if (toastTimeouts.has(toastId)) {
    return;
  }
  const timeout = setTimeout(() => {
    toastTimeouts.delete(toastId);
    remove(toastId);
  }, 1000);
  toastTimeouts.set(toastId, timeout);
};

const clearFromRemoveQueue = (toastId: Toast['id']) => {
  const timeout = toastTimeouts.get(toastId);
  if (timeout) {
    clearTimeout(timeout);
  }
};

export function update(toast: Partial<Toast>) {
  if (toast.id) {
    clearFromRemoveQueue(toast.id);
  }
  toasts.update(($toasts) => $toasts.map((t) => (t.id === toast.id ? { ...t, ...toast } : t)));
}

export function add(toast: Toast) {
  toasts.update(($toasts) => [toast, ...$toasts].slice(0, TOAST_LIMIT));
}

export function upsert(toast: Toast) {
  if (get(toasts).find((t) => t.id === toast.id)) {
    update(toast);
  } else {
    add(toast);
  }
}

export function dismiss(toastId?: Toast['id']) {
  toasts.update(($toasts) => {
    if (toastId) {
      addToRemoveQueue(toastId);
    } else {
      $toasts.forEach((toast) => {
        addToRemoveQueue(toast.id);
      });
    }
    return $toasts.map((t) =>
      t.id === toastId || toastId === undefined ? { ...t, visible: false } : t,
    );
  });
}

export function remove(toastId?: Toast['id']) {
  toasts.update(($toasts) => {
    if (toastId === undefined) {
      return [];
    }
    return $toasts.filter((t) => t.id !== toastId);
  });
}

export function startPause(time: number) {
  pausedAt.set(time);
}

export function endPause(time: number) {
  let diff = 0;
  pausedAt.update(($pausedAt) => {
    diff = time - ($pausedAt || 0);
    return null;
  });
  toasts.update(($toasts) =>
    $toasts.map((t) => ({
      ...t,
      pauseDuration: t.pauseDuration + diff,
    })),
  );
}

const defaultTimeouts: Record<ToastType, number> = {
  blank: 4000,
  error: 4000,
  success: 2000,
  loading: Infinity,
  custom: 4000,
};

export function useToasterStore(toastOptions: DefaultToastOptions = {}) {
  const mergedToasts = writableDerived(
    toasts,
    ($toasts) =>
      $toasts.map((t) => ({
        ...toastOptions,
        ...toastOptions[t.type],
        ...t,
        duration:
          t.duration ||
          toastOptions[t.type]?.duration ||
          toastOptions?.duration ||
          defaultTimeouts[t.type],
        style: [toastOptions.style, toastOptions[t.type]?.style, t.style].join(';'),
      })),
    ($toasts: Toast[]) => $toasts,
  );

  return {
    toasts: mergedToasts,
    pausedAt,
  };
}
