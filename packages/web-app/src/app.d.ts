// See https://kit.svelte.dev/docs/types#app
// for information about these interfaces
declare global {
  interface Window {
    // The app layout's dialer, for pages that drive it (campaign calls) and
    // for the e2e tests.

    dialerWidget?: any;
  }

  namespace App {
    // interface Error {}
    // interface Locals {}
    // interface PageData {}
    // interface Platform {}
  }
}

export {};
