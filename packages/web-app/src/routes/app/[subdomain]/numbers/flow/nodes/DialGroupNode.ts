import type { DialGroupNodeData } from '$lib/server/types/DialGroupNodeData';

import DialNodeComponent from './DialGroupNode.svelte';
import { FlowNode } from './FlowNode';
import { v4 as uuidv4 } from 'uuid';

export class DialGroupNode extends FlowNode {
  data: DialGroupNodeData;
  component = DialNodeComponent;
  constructor(data?: DialGroupNodeData) {
    super();
    if (data) {
      this.data = data;
    } else {
      this.data = {
        id: uuidv4(),
        type: 'DialGroup',
        data: {
          to: [],
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
