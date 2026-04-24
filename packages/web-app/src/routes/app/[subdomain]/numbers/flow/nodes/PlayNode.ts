import PlayNodeComponent from './PlayNode.svelte';
import { v4 as uuidv4 } from 'uuid';
import { FlowNode } from './FlowNode';
import type { PlayNodeData } from '$lib/types/PlayNodeData';

export class PlayNode extends FlowNode {
  data: PlayNodeData;
  component = PlayNodeComponent;
  constructor(data?: PlayNodeData) {
    super();
    if (data) {
      this.data = data;
    } else {
      this.data = {
        id: uuidv4(),
        type: 'Play',
        data: {
          media: '',
        },
      };
    }
  }

  linkOutletToInlet() {
    return null;
  }
}
