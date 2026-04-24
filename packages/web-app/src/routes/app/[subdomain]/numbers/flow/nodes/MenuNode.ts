import MenuComponent from './MenuNode.svelte';
import { v4 as uuidv4 } from 'uuid';
import { FlowNode } from './FlowNode';
import type { MenuNodeData } from '$lib/types/MenuNodeData';

export class MenuNode extends FlowNode {
  data: MenuNodeData;
  component = MenuComponent;
  constructor(data?: MenuNodeData) {
    super();
    if (data) {
      this.data = data;
    } else {
      this.data = {
        id: uuidv4(),
        type: 'Menu',
        data: {
          promptAudio: '',
          errorAudio: '',
          repeat: 3,
          afterPromptWaitTime: 3,
          multiDigitWaitTime: 3,
        },
        outlets: {},
      };
    }
  }

  linkOutletToInlet(outletId: string, inletId: string) {
    this.data.outlets[outletId] = inletId;
  }
}
