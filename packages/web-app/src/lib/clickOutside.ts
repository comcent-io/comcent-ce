export function clickOutside(element: HTMLElement, callbackFunction: () => void) {
  let callbackCopy = callbackFunction;
  function onClick(event: any) {
    if (!element.contains(event.target)) {
      callbackCopy();
    }
  }

  document.body.addEventListener('click', onClick);

  return {
    update(newCallbackFunction: () => void) {
      callbackCopy = newCallbackFunction;
    },
    destroy() {
      document.body.removeEventListener('click', onClick);
    },
  };
}
