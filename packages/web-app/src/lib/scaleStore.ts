import { writable } from 'svelte/store';

export const INITIAL_SCALE = 9;
export const scale = writable(INITIAL_SCALE);
