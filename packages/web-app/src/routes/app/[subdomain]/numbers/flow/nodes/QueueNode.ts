import QueueNodeComponent from './QueueNode.svelte';
import { v4 as uuidv4 } from 'uuid';
import { FlowNode } from './FlowNode';
import type { QueueNodeData } from '$lib/types/QueueNodeData';

export class QueueNode extends FlowNode {
  data: QueueNodeData;
  component = QueueNodeComponent;
  constructor(data?: QueueNodeData) {
    super();
    if (data) {
      this.data = data;
    } else {
      this.data = {
        id: uuidv4(),
        type: 'Queue',
        data: {
          queue: '',
        },
      };
    }
  }

  linkOutletToInlet() {
    return null;
  }
}
