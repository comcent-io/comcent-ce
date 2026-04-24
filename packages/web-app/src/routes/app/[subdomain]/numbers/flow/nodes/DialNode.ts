import type { DialNodeData } from '$lib/server/types/DialNodeData';

import DialNodeComponent from './DialNode.svelte';
import { FlowNode } from './FlowNode';
import { v4 as uuidv4 } from 'uuid';

export class DialNode extends FlowNode {
  data: DialNodeData;
  component = DialNodeComponent;
  constructor(data?: DialNodeData) {
    super();
    if (data) {
      this.data = data;
    } else {
      this.data = {
        id: uuidv4(),
        type: 'Dial',
        data: {
          to: '',
          shouldSpoof: false,
          timeout: 20,
        },
        outlets: {
          timeout: '',
        },
      };
    }
  }

  linkOutletToInlet(outletId: 'timeout', inletId: string) {
    this.data.outlets.timeout = inletId;
  }
}
